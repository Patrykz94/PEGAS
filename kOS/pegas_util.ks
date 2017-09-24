//	Utility library.

//	INTERNAL FUNCTIONS

//	Rodrigues vector rotation formula
FUNCTION rodrigues {
	DECLARE PARAMETER inVector.	//	Expects a vector
	DECLARE PARAMETER axis.		//	Expects a vector
	DECLARE PARAMETER angle.	//	Expects a scalar
	
	SET axis TO axis:NORMALIZED.
	
	LOCAL outVector IS inVector*COS(angle).
	SET outVector TO outVector + VCRS(axis, inVector)*SIN(angle).
	SET outVector TO outVector + axis*VDOT(axis, inVector)*(1-COS(angle)).
	
	RETURN outVector.
}.

//	KSP-MATLAB-KSP vector conversion
FUNCTION vecYZ {
	DECLARE PARAMETER input.	//	Expects a vector
	LOCAL output IS V(input:X, input:Z, input:Y).
	RETURN output.
}.

//	Engine combination parameters
FUNCTION getThrust {
	DECLARE PARAMETER engines.	//	Expects a list of lexicons
	
	LOCAL n IS engines:LENGTH.
	LOCAL F IS 0.
	LOCAL dm IS 0.
	FROM { LOCAL i IS 0. } UNTIL i>=n STEP { SET i TO i+1. } DO {
		LOCAL isp IS engines[i]["isp"].
		LOCAL dm_ IS engines[i]["flow"].
		SET dm TO dm + dm_.
		SET F TO F + isp*dm_*g0.
	}
	SET isp TO F/(dm*g0).
	
	RETURN LIST(F, dm, isp).
}.

//	TARGETING FUNCTIONS

//	Generate a PEGAS-compatible target struct from user-specified one
FUNCTION targetSetup {
	//	Expects a global variable "mission" as lexicon
	
	//	Fix target definition if the burnout altitude is wrong or not given
	IF mission:HASKEY("altitude") {
		IF mission["altitude"] < mission["periapsis"] OR mission["altitude"] > mission["apoapsis"] {
			SET mission["altitude"] TO mission["periapsis"].
		}
	} ELSE {
		mission:ADD("altitude", mission["periapsis"]).
	}
	
	//	Override plane definition if a map target was selected
	IF HASTARGET {
		SET mission["inclination"] TO TARGET:ORBIT:INCLINATION.
		SET mission["LAN"] TO TARGET:ORBIT:LAN.
	}
	
	//	Fix LAN to between 0-360 degrees
	IF mission["LAN"] < 0 { SET mission["LAN"] TO mission["LAN"] + 360. }
	IF mission["LAN"] > 360 { SET mission["LAN"] TO mission["LAN"] - 360. }
	
	//	Calculate velocity and flight path angle at given criterion using vis-viva equation and conservation of specific relative angular momentum
	LOCAL pe IS mission["periapsis"]*1000 + SHIP:BODY:RADIUS.
	LOCAL ap IS mission["apoapsis"]*1000 + SHIP:BODY:RADIUS.
	LOCAL targetAltitude IS mission["altitude"]*1000 + SHIP:BODY:RADIUS.
	LOCAL sma IS (pe+ap) / 2.							//	semi-major axis
	LOCAL vpe IS SQRT(SHIP:BODY:MU * (2/pe - 1/sma)).	//	velocity at periapsis
	LOCAL srm IS pe * vpe.								//	specific relative angular momentum
	LOCAL targetVelocity IS SQRT(SHIP:BODY:MU * (2/targetAltitude - 1/sma)).
	LOCAL flightPathAngle IS ARCCOS( srm/(targetVelocity*targetAltitude) ).
	
	RETURN LEXICON(
				"radius", targetAltitude,
				"velocity", targetVelocity,
				"angle", flightPathAngle,
				"normal", V(0,0,0)				//	temporarily unset - due to KSP's silly coordinate system this needs to be recalculated every time step, so we will not bother with it for now
				).
}.

//	Time to next northerly launch opportunity
FUNCTION orbitInterceptTime {
	//	Expects a global variable "mission" as lexicon
	LOCAL targetInc IS mission["inclination"].
	LOCAL targetLan IS mission["lan"].
	
	//	First find the ascending node of an orbit of the given inclination, passing right over the vehicle now.
	LOCAL b IS TAN(90-targetInc)*(TAN(SHIP:GEOPOSITION:LAT)).	//	From Napier's spherical triangle mnemonics
	IF b < -1 { SET b TO -1. }
	IF b > 1 { SET b TO 1. }
	SET b TO ARCSIN(b).											//	Broken in case of an attempt at launch to a lower inclination than reachable
	LOCAL currentNode IS VXCL(V(0,1,0), -SHIP:ORBIT:BODY:POSITION):NORMALIZED.
	SET currentNode TO rodrigues(currentNode, V(0,1,0), b).
	//	Then find the ascending node of the target orbit.
	LOCAL targetNode IS rodrigues(SOLARPRIMEVECTOR, V(0,1,0), -targetLan).
	//	Finally find the angle between them, minding rotation direction.
	LOCAL nodeDelta IS VANG(currentNode, targetNode).
	LOCAL deltaDir IS VDOT(V(0,1,0), VCRS(targetNode, currentNode)).
	IF deltaDir < 0 { SET nodeDelta TO 360 - nodeDelta. }
	LOCAL deltaTime IS SHIP:ORBIT:BODY:ROTATIONPERIOD * nodeDelta/360.
	
	RETURN deltaTime.
}.

//	Launch azimuth to a given orbit
FUNCTION launchAzimuth {
	//	Expects global variables "upfgTarget" and "mission" as lexicons
	
	LOCAL targetInc IS mission["inclination"].
	LOCAL targetAlt IS upfgTarget["radius"].
	LOCAL targetVel IS upfgTarget["velocity"].
	LOCAL siteLat IS SHIP:GEOPOSITION:LAT.
	IF targetInc < siteLat { pushUIMessage( "Target inclination below launch site latitude!", 5, PRIORITY_HIGH ). }
	
	LOCAL Binertial IS COS(targetInc)/COS(siteLat).
	IF Binertial < -1 { SET Binertial TO -1. }
	IF Binertial > 1 { SET Binertial TO 1. }
	SET Binertial TO ARCSIN(Binertial).		//	In case of an attempt at launch to a lower inclination than reachable
	//LOCAL Vorbit IS SQRT( SHIP:ORBIT:BODY:MU/(SHIP:BODY:RADIUS+targetAlt*1000) ).		//	This is a normal calculation for a circular orbit
	LOCAL Vorbit IS targetVel*COS(upfgTarget["angle"]).									//	But we already have our desired velocity, however we must correct for the flight path angle (only the tangential component matters here)
	LOCAL Vbody IS (2*CONSTANT:PI*SHIP:BODY:RADIUS/SHIP:BODY:ROTATIONPERIOD)*COS(siteLat).
	LOCAL VrotX IS Vorbit*SIN(Binertial)-Vbody.
	LOCAL VrotY IS Vorbit*COS(Binertial).
	LOCAL azimuth IS ARCTAN2(VrotY, VrotX).
	
	RETURN 90-azimuth.	//	In MATLAB an azimuth of 0 is due east, while in KSP it's due north. This returned value is steering-ready.
}.

// Creating a vector from the roll angle provided
FUNCTION getRollVector {
	DECLARE PARAMETER rollAngle.		// Expects scalar

	IF rollRequired {
		LOCAL angle IS angleaxis(rollAngle, SHIP:FACING:FOREVECTOR).
		LOCAL rollVector IS SHIP:UP:VECTOR * angle.

		RETURN rollVector.
	} ELSE {
		RETURN SHIP:FACING:TOPVECTOR.
	}
}.

//	Verifies parameters of the attained orbit
FUNCTION missionValidation {
	FUNCTION difference {
		DECLARE PARAMETER input.		//	Expects scalar
		DECLARE PARAMETER reference.	//	Expects scalar
		DECLARE PARAMETER threshold.	//	Expects scalar
		
		IF ABS(input-reference)<threshold { RETURN TRUE. } ELSE { RETURN FALSE. }
	}
	FUNCTION errorMessage {
		DECLARE PARAMETER input.		//	Expects scalar
		DECLARE PARAMETER reference.	//	Expects scalar
		//	Apoapse/periapse will be rounded to no decimal places, angles rounded to 2.
		LOCAL smartRounding IS 0.
		LOCAL inputAsString IS "" + ROUND(input,0).
		IF inputAsString:LENGTH <= 3 {
			SET smartRounding TO 2.
		}
		RETURN "" + ROUND(input,smartRounding) + " vs " + ROUND(reference,smartRounding) + " (" + ROUND(100*(input-reference)/reference,1) + "%)".
	}
	//	Expects global variable "mission" as lexicon.
	
	//	Some local variables for tracking mission success/partial success/failure
	LOCAL success IS TRUE.
	LOCAL failure IS FALSE.
	LOCAL apsisSuccessThreshold IS 10000.
	LOCAL apsisFailureThreshold IS 50000.
	LOCAL angleSuccessThreshold IS 0.1.
	LOCAL angleFailureThreshold IS 1.
	
	//	Check every condition
	IF NOT difference(SHIP:ORBIT:PERIAPSIS, mission["periapsis"]*1000, apsisSuccessThreshold) {
		SET success TO FALSE.
		IF NOT difference(SHIP:ORBIT:PERIAPSIS, mission["periapsis"]*1000, apsisFailureThreshold) {
			SET failure TO TRUE.
		}
		PRINT "Periapsis:   " + errorMessage(SHIP:ORBIT:PERIAPSIS, mission["periapsis"]*1000).
	}
	IF NOT difference(SHIP:ORBIT:APOAPSIS, mission["apoapsis"]*1000, apsisSuccessThreshold) {
		SET success TO FALSE.
		IF NOT difference(SHIP:ORBIT:APOAPSIS, mission["apoapsis"]*1000, apsisFailureThreshold) {
			SET failure TO TRUE.
		}
		PRINT "Apoapsis:    " + errorMessage(SHIP:ORBIT:APOAPSIS, mission["apoapsis"]*1000).
	}
	IF NOT difference(SHIP:ORBIT:INCLINATION, mission["inclination"], angleSuccessThreshold) {
		SET success TO FALSE.
		IF NOT difference(SHIP:ORBIT:INCLINATION, mission["inclination"], angleFailureThreshold) {
			SET failure TO TRUE.
		}
		PRINT "Inclination: " + errorMessage(SHIP:ORBIT:INCLINATION, mission["inclination"]).
	}
	IF NOT difference(SHIP:ORBIT:LAN, mission["LAN"], angleSuccessThreshold) {
		SET success TO FALSE.
		IF NOT difference(SHIP:ORBIT:LAN, mission["LAN"], angleFailureThreshold) {
			SET failure TO TRUE.
		}
		PRINT "Long. of AN: " + errorMessage(SHIP:ORBIT:LAN, mission["LAN"]).
	}
	
	//	If at least one condition is not a success - we only have a partial. If at least one condition
	//	is a failure - we have a failure.
	IF failure {
		pushUIMessage( "Mission failure!", PRIORITY_HIGH ).
	} ELSE {
		IF NOT success {
			pushUIMessage( "Partial success.", PRIORITY_HIGH ).
		} ELSE {
			pushUIMessage( "Mission successful!", PRIORITY_HIGH ).
		}
	}
}

//	UPFG HANDLING FUNCTIONS

//	Creates and initializes UPFG internal struct
FUNCTION setupUPFG {
	//	Expects global variables "mission", "upfgState" and "upfgTarget" as lexicons.

	LOCAL curR IS upfgState["radius"].
	LOCAL curV IS upfgState["velocity"].

	SET upfgTarget["normal"] TO targetNormal(mission["inclination"], mission["LAN"]).
	LOCAL desR IS rodrigues(curR, -upfgTarget["normal"], 20):NORMALIZED * upfgTarget["radius"].
	LOCAL tgoV IS upfgTarget["velocity"] * VCRS(-upfgTarget["normal"], desR):NORMALIZED - curV.

	RETURN LEXICON(
		"cser", LEXICON("dtcp",0, "xcp",0, "A",0, "D",0, "E",0),
		"rbias", V(0, 0, 0),
		"rd", desR,
		"rgrav", -SHIP:ORBIT:BODY:MU/2 * curR / curR:MAG^3,
		"tb", 0,
		"time", upfgState["time"],
		"tgo", 0,
		"v", curV,
		"vgo", tgoV
	).
}.

//	Acquire vehicle position data
FUNCTION acquireState {
	//	Expects a global variable "liftoffTime" as scalar
	
	RETURN LEXICON(
		"time", TIME:SECONDS - liftoffTime:SECONDS,
		"mass", SHIP:MASS*1000,
		"radius", vecYZ(SHIP:ORBIT:BODY:POSITION) * -1,
		"velocity", vecYZ(SHIP:ORBIT:VELOCITY:ORBIT)
	).
}.

//	Target plane normal vector in MATLAB coordinates, UPFG compatible direction
FUNCTION targetNormal {
	DECLARE PARAMETER targetInc.	//	Expects a scalar
	DECLARE PARAMETER targetLan.	//	Expects a scalar
	
	//	First create a vector pointing to the highest point in orbit by rotating the prime vector by a right angle.
	LOCAL highPoint IS rodrigues(SOLARPRIMEVECTOR, V(0,1,0), 90-targetLan).
	//	Then create a temporary axis of rotation (short form for 90 deg rotation).
	LOCAL rotAxis IS V(-highPoint:Z, highPoint:Y, highPoint:X).
	//	Finally rotate about this axis by a right angle to produce normal vector.
	LOCAL normalVec IS rodrigues(highPoint, rotAxis, 90-targetInc).
	
	RETURN -vecYZ(normalVec).
}.

//	EVENT HANDLING FUNCTIONS

//	Setup system events, currently only countdown messages
FUNCTION setSystemEvents {
	//	Local function - countdown event generator
	FUNCTION makeEvent {
		DECLARE PARAMETER timeAfterLiftoff.	//	Expects a scalar
		DECLARE PARAMETER eventMessage.		//	Expects a string
		
		RETURN LEXICON("time", timeAfterLiftoff, "type", "dummy", "message", eventMessage, "data", LIST()).
	}.
	
	//	Expects a global variable "liftoffTime" as scalar and "systemEvents" as list
	LOCAL timeToLaunch IS liftoffTime:SECONDS - TIME:SECONDS.
	
	//	Prepare events table
	IF timeToLaunch > 18000 { systemEvents:ADD(makeEvent(-18000,"5 hours to launch")). }
	IF timeToLaunch > 3600  { systemEvents:ADD(makeEvent(-3600,"1 hour to launch")). }
	IF timeToLaunch > 1800  { systemEvents:ADD(makeEvent(-1800,"30 minutes to launch")). }
	IF timeToLaunch > 600   { systemEvents:ADD(makeEvent(-600,"10 minutes to launch")). }
	IF timeToLaunch > 300   { systemEvents:ADD(makeEvent(-300,"5 minutes to launch")). }
	IF timeToLaunch > 60    { systemEvents:ADD(makeEvent(-60,"1 minute to launch")). }
	IF timeToLaunch > 30	{ systemEvents:ADD(makeEvent(-30,"30 seconds to launch")). }
	systemEvents:ADD(makeEvent(-10,"10 SECONDS TO LAUNCH")).
	systemEvents:ADD(makeEvent(-9,"9 SECONDS TO LAUNCH")).
	systemEvents:ADD(makeEvent(-8,"8 SECONDS TO LAUNCH")).
	systemEvents:ADD(makeEvent(-7,"7 SECONDS TO LAUNCH")).
	systemEvents:ADD(makeEvent(-6,"6 SECONDS TO LAUNCH")).
	systemEvents:ADD(makeEvent(-5,"5 SECONDS TO LAUNCH")).
	systemEvents:ADD(makeEvent(-4,"4 SECONDS TO LAUNCH")).
	systemEvents:ADD(makeEvent(-3,"3 SECONDS TO LAUNCH")).
	systemEvents:ADD(makeEvent(-2,"2 SECONDS TO LAUNCH")).
	systemEvents:ADD(makeEvent(-1,"1 SECONDS TO LAUNCH")).
	
	//	Initialize the first event
	systemEventHandler().
}.

//	Setup user events (vehicle sequence)
FUNCTION setUserEvents {
	//	Just a wrapper to a handler which automatically does the setup on its first run.
	userEventHandler().
}.

//	Setup vehicle: transform user input to UPFG-compatible struct
FUNCTION setVehicle {
	//	Calculates missing mass inputs (user gives any 2 of 3: total, dry, fuel mass)
	//	Adds payload mass to the mass of each stage
	//	Sets up defaults: acceleration limit (none, 0.0), throttle (1.0), and UPFG MODE
	//	Calculates engine fuel mass flow (if thrust value was given instead) and adjusts for given throttle
	//	Calculates max stage burn time
	
	//	Expects a global variable "vehicle" as list of lexicons and "controls" and "mission" as lexicon.

	LOCAL i IS 0.
	FOR v IN vehicle {
		//	Mass calculations
		IF v:HASKEY("massTotal") AND v:HASKEY("massDry")		{ v:ADD("massFuel",  v["massTotal"]-v["massDry"]).	}
		ELSE IF v:HASKEY("massTotal") AND v:HASKEY("massFuel")	{ v:ADD("massDry",   v["massTotal"]-v["massFuel"]).	}
		ELSE IF v:HASKEY("massFuel") AND v:HASKEY("massDry")	{ v:ADD("massTotal", v["massFuel"] +v["massDry"]).	}
		ELSE { PRINT "Vehicle is ill-defined: missing mass keys in stage " + i. }
		IF mission:HASKEY("payload") {
			SET v["massTotal"] TO v["massTotal"] + mission["payload"].
			SET v["massDry"] TO v["massDry"] + mission["payload"].
		}
		//	Default fields: gLim, throttle, m0, mode
		IF NOT v:HASKEY("gLim")		{ v:ADD("gLim", 0). }
		IF NOT v:HASKEY("throttle")	{ v:ADD("throttle", 1). }
		v:ADD("m0", v["massTotal"]).
		v:ADD("mode", 1).
		//	Engine update
		FOR e IN v["engines"] {
			IF NOT e:HASKEY("flow") { e:ADD("flow", e["thrust"] / (e["isp"]*g0) * v["throttle"]). }
		}
		//	Calculate max burn time
		LOCAL combinedEngines IS getThrust(v["engines"]).
		v:ADD("maxT", v["massFuel"] / combinedEngines[1]).
		//	Increment loop counter
		SET i TO i+1.
	}
}.

//	Handles definition of the physical vehicle (initial mass of the first actively guided stage, acceleration limits) and
//	initializes the automatic staging sequence.
FUNCTION initializeVehicle {
	//	The first actively guided stage can be a whole new stage (think: Saturn V, S-II), or a sustainer stage that continues
	//	a burn started at liftoff (Atlas V, STS). In the former case, all information is known at liftoff and no updates are
	//	necessary. For the latter, the amount of fuel remaining in the tank is only known at the moment of ignition of the
	//	stage (due to uncertainty in engine spool-up at ignition, and potentially changing time of activation of UPFG). Thus,
	//	the stage - and potentially also its derived const-acc stage - can only be initialized in flight. And this is what the
	//	following function is supposed to do.

	//	Expects a global variable "vehicle" as list of lexicons, "upfgConvergenceDelay" as scalar
	
	LOCAL currentTime IS TIME:SECONDS.
	LOCAL currentMass IS SHIP:MASS*1000.
	//	If a stage has a staging sequence defined, this means it is a Saturn-like stage which needs no update. Otherwise,
	//	it is a sustainer stage and only its initial (and, hence, dry) mass is known. Actual mass needs to be calculated.
	IF NOT vehicle[0]["staging"]["ignition"] {
		LOCAL combinedEngines IS getThrust(vehicle[0]["engines"]).
		//	This function is expected to run "upfgConvergenceDelay" before actual activation of the stage, hence the mass decrease.
		SET vehicle[0]["massTotal"] TO currentMass - combinedEngines[1]*upfgConvergenceDelay.
		SET vehicle[0]["massFuel"]  TO vehicle[0]["massTotal"] - vehicle[0]["massDry"].
		SET vehicle[0]["m0"] TO vehicle[0]["massTotal"].
		SET vehicle[0]["maxT"] TO vehicle[0]["massFuel"] / combinedEngines[1].
	}
	//	Acceleration limits are handled in the following loop
	FROM { LOCAL i IS 0. } UNTIL i = vehicle:LENGTH STEP { SET i TO i+1. } DO {
		IF vehicle[i]["gLim"]>0 {
			//	Calculate when will the acceleration limit be exceeded
			LOCAL fdmisp IS getThrust(vehicle[i]["engines"]).
			LOCAL Fthrust IS fdmisp[0].
			LOCAL massFlow IS fdmisp[1].
			LOCAL totalIsp IS fdmisp[2].
			LOCAL accLimTime IS (vehicle[i]["m0"] - Fthrust/vehicle[i]["gLim"]/g0) / massFlow.
			//	If this time is greater than the stage's max burn time - we're good. Otherwise, the limit must be enforced
			IF accLimTime < vehicle[i]["maxT"] {
				//	Create a new stage
				LOCAL gLimStage IS LEXICON("mode", 2, "name", "Constant acceleration", "gLim", vehicle[i]["gLim"], "engines", vehicle[i]["engines"]).
				//	Inherit default throttle from the original stage
				gLimStage:ADD("throttle", vehicle[i]["throttle"]).
				//	Supply it with a staging information
				gLimStage:ADD("staging", LEXICON("jettison", FALSE, "ignition", FALSE)).
				//	Calculate its initial mass
				LOCAL burnedFuelMass IS massFlow * accLimTime.
				gLimStage:ADD("m0", vehicle[i]["m0"] - burnedFuelMass).
				//	Calculate its burn time assuming constant acceleration
				LOCAL totalStageFuel IS massFlow * vehicle[i]["maxT"].
				LOCAL remainingFuel IS vehicle[i]["massFuel"] - burnedFuelMass.
				gLimStage:ADD("maxT", totalIsp/vehicle[i]["gLim"] * LN( gLimStage["m0"]/(gLimStage["m0"]-remainingFuel) )).
				//	Insert it into the list and increment i so that we don't process it next
				vehicle:INSERT(i+1, gLimStage).
				//	Adjust the current stage's burn time
				SET vehicle[i]["maxT"] TO accLimTime.
				SET vehicle[i]["gLim"] TO 0.
				SET i TO i+1.
			}
		}
	}
	stageEventHandler(currentTime).	//	Schedule ignition of the first UPFG-controlled stage.
}

//	Executes a system event. Currently only supports message printing.
FUNCTION systemEventHandler {
	//	Local function needed here, so we can safely exit the handler on first run without excessive nesting
	FUNCTION setNextEvent {
		SET systemEventPointer TO systemEventPointer + 1.
		IF systemEventPointer < systemEvents:LENGTH {
			WHEN TIME:SECONDS >= liftoffTime:SECONDS + systemEvents[systemEventPointer]["time"] THEN { SET systemEventFlag TO TRUE. }
		}
	}.
	
	//	Expects global variables "liftoffTime" as TimeSpan, "systemEvents" as list, "systemEventFlag" as bool and "systemEventPointer" as scalar.
	//	First call initializes and exits without messaging
	IF systemEventPointer = -1 {	//	This var is initialized at -1, so meeting this condition is only possible on first run.
		setNextEvent().
		RETURN.
	}
	
	//	Handle event
	pushUIMessage( systemEvents[systemEventPointer]["message"], 3, PRIORITY_LOW ).
	
	//	Reset event flag
	SET systemEventFlag TO FALSE.
	
	//	Create new event
	setNextEvent().
}.

//	Executes a user (sequence) event.
FUNCTION userEventHandler {
	//	Mechanism is very similar to systemEventHandler
	FUNCTION setNextEvent {
		SET userEventPointer TO userEventPointer + 1.
		IF userEventPointer < sequence:LENGTH {
			WHEN TIME:SECONDS >= liftoffTime:SECONDS + sequence[userEventPointer]["time"] THEN { SET userEventFlag TO TRUE. }
		}
	}.
	
	//	Expects global variables "liftoffTime" as scalar, "sequence" as list, "userEventFlag" as bool and "userEventPointer" as scalar.
	//	First call initializes and exits without doing anything
	IF userEventPointer = -1 {
		setNextEvent().
		RETURN.
	}
	
	//	Handle event
	LOCAL eType IS sequence[userEventPointer]["type"].
	IF      eType = "print" OR eType = "p" { }
	ELSE IF eType = "stage" OR eType = "s" { STAGE. }
	ELSE IF eType = "throttle" OR eType = "t" { SET throttleSetting TO sequence[userEventPointer]["throttle"]. }
	ELSE IF eType = "roll" OR eType = "r" { SET rollAngle TO sequence[userEventPointer]["angle"]. SET rollRequired TO TRUE. }
	ELSE { pushUIMessage( "Unknown event type (" + eType + ", message='" + sequence[userEventPointer]["message"] + "')!", 5, PRIORITY_HIGH ). }
	pushUIMessage( sequence[userEventPointer]["message"] ).
	
	//	Reset event flag
	SET userEventFlag TO FALSE.
	
	//	Create new event
	setNextEvent().
}.

//	Executes an automatic staging event. Spawns additional triggers.
FUNCTION stageEventHandler {
	//	Structure is very similar to systemEventHandler, but with a little twist.
	//	Before activating a stage, the vehicle's attitude is held constant. During this period, to save time and ignite the new stage
	//	with UPFG at least closer to convergence, we want to calculate steering for the next stage. Therefore, we decide that the
	//	phrase "current stage" shall mean "the currently guided stage, or the one that will be guided next if this one is almost spent".
	//	Global variable "upfgStage" shall point to this exact stage and must be incremented at the very moment we decide to solve for
	//	the next stage: upon setting the global variable "stagingInProgress".
	FUNCTION setNextEvent {
		DECLARE PARAMETER baseTime IS TIME:SECONDS.	//	Expects a scalar. Meaning: set next stage from this time (allows more precise calculations)
		DECLARE PARAMETER eventDelay IS 0.			//	Expects a scalar. Meaning: if this stage ignites in "eventDelay" seconds from now, the next should ignite in "eventDelay"+"maxT" from now.
		IF upfgStage < vehicle:LENGTH-1 {
			GLOBAL nextStageTime IS baseTime + eventDelay + vehicle[upfgStage]["maxT"].
			WHEN TIME:SECONDS >= nextStageTime THEN { SET stageEventFlag TO TRUE. }
			WHEN TIME:SECONDS >= nextStageTime - stagingKillRotTime THEN {
				SET stagingInProgress TO TRUE.
				SET upfgStage TO upfgStage + 1.
				upfgStagingNotify().	//	Pass information about staging to UPFG handler
			}
		}
	}.
	
	//	Expects global variables "liftOffTime" as TimeSpan, "vehicle" as list, "controls" as lexicon, "upfgStage" as scalar and "stageEventFlag" as bool.
	DECLARE PARAMETER currentTime IS TIME:SECONDS.	//	Only passed when run from initializeVehicle
	LOCAL currentMass IS SHIP:MASS*1000.
	
	//	First call (we know because upfgStage is still at initial value) only sets up the event for first guided stage.
	IF upfgStage = -1 {
		//	We cannot use setNextEvent because it directly reads vehicle[upfgStage], but we have to do a part of its job
		GLOBAL nextStageTime IS liftOffTime:SECONDS + controls["upfgActivation"].
		WHEN TIME:SECONDS >= nextStageTime THEN { SET stageEventFlag TO TRUE. }
		SET upfgStage TO upfgStage + 1.
		RETURN.
	}
	
	//	Handle event
	LOCAL event IS vehicle[upfgStage]["staging"].
	LOCAL stageName IS vehicle[upfgStage]["name"].
	LOCAL eventDelay IS 0.			//	Many things occur sequentially - this keeps track of the time between subsequent events.
	IF event["jettison"] {
		GLOBAL stageJettisonTime IS currentTime + event["waitBeforeJettison"].
		WHEN TIME:SECONDS >= stageJettisonTime THEN {	STAGE.
														pushUIMessage(stageName + " - separation"). }
		SET eventDelay TO eventDelay + event["waitBeforeJettison"].
	}
	IF event["ignition"] {
		IF event["ullage"] = "rcs" {
			GLOBAL ullageIgnitionTime IS currentTime + eventDelay + event["waitBeforeIgnition"].
			WHEN TIME:SECONDS >= ullageIgnitionTime THEN {	RCS ON. 
															SET SHIP:CONTROL:FORE TO 1.0.
															pushUIMessage(stageName + " - RCS ullage on"). }
			SET eventDelay TO eventDelay + event["waitBeforeIgnition"].
			GLOBAL engineIgnitionTime IS currentTime + eventDelay + event["ullageBurnDuration"].
			WHEN TIME:SECONDS >= engineIgnitionTime THEN {	STAGE.
															SET stagingInProgress TO FALSE.
															pushUIMessage(stageName + " - ignition"). }
			SET eventDelay TO eventDelay + event["ullageBurnDuration"].
			GLOBAL ullageShutdownTime IS currentTime + eventDelay + event["postUllageBurn"].
			WHEN TIME:SECONDS >= ullageShutdownTime THEN {	SET SHIP:CONTROL:FORE TO 0.0.
															RCS OFF.
															pushUIMessage(stageName + " - RCS ullage off"). }
		} ELSE IF event["ullage"] = "srb" {
			GLOBAL ullageIgnitionTime IS currentTime + eventDelay + event["waitBeforeIgnition"].
			WHEN TIME:SECONDS >= ullageIgnitionTime THEN {	STAGE.
															pushUIMessage(stageName + " - SRB ullage ignited"). }
			SET eventDelay TO eventDelay + event["waitBeforeIgnition"].
			GLOBAL engineIgnitionTime IS currentTime + eventDelay + event["ullageBurnDuration"].
			WHEN TIME:SECONDS >= engineIgnitionTime THEN {	STAGE.
															SET stagingInProgress TO FALSE.
															pushUIMessage(stageName + " - ignition"). }
			SET eventDelay TO eventDelay + event["ullageBurnDuration"].
		} ELSE IF event["ullage"] = "none" {
			GLOBAL engineIgnitionTime IS currentTime + eventDelay + event["waitBeforeIgnition"].
			WHEN TIME:SECONDS >= engineIgnitionTime THEN {	STAGE.
															SET stagingInProgress TO FALSE.
															pushUIMessage(stageName + " - ignition"). }
			SET eventDelay TO eventDelay + event["waitBeforeIgnition"].
		} ELSE { pushUIMessage( "Unknown event type (" + event["ullage"] + ")!", 5, PRIORITY_HIGH ). }
	} ELSE {
		//	If this event does not need ignition, staging is over at this moment
		SET stagingInProgress TO FALSE.
	}
	pushUIMessage(stageName + " - activation").
	
	//	Reset event flag
	SET stageEventFlag TO FALSE.
	
	//	Create new event
	setNextEvent(currentTime, eventDelay).
}.

//	THROTTLE AND STEERING CONTROLS

//	Interface between stageEventHandler and upfgSteeringControl.
FUNCTION upfgStagingNotify {
	//	Allows stageEventHandler to let upfgSteeringControl know that staging had occured.
	//	Easier to modify this function in case more information needs to be passed rather
	//	than stageEventHandler itself.
	
	//	Expects global variables "upfgConverged" and "usc_stagingNoticed" as bool.
	SET upfgConverged TO FALSE.
	SET usc_stagingNoticed TO FALSE.
}

//	Intelligent wrapper around UPFG that controls steering vector.
FUNCTION upfgSteeringControl {
	//	This function is essentially oblivious to which stage it is guiding (see "stageEventHandler" for more info).
	//	However, it pays attention to UPFG convergence and proceeding staging, ensuring that the vehicle will not
	//	rotate during separation nor will it rotate to an oscillating, unconverged solution.
	FUNCTION resetUPFG {
		//	Reset internal state of the guidance algorithm. Put here as a precaution from early debugging days,
		//	should not be ever called in normal operation (but if it gets called, it's likely to fix UPFG going
		//	crazy).
		//	Important thing to do is to remember fuel burned in the stage before resetting (or set it to zero if
		//	we're in a pre-convergence phase).
		LOCAL tb IS 0.
		IF NOT stagingInProgress { SET tb TO upfgOutput[0]["tb"]. }
		SET upfgOutput[0] TO setupUPFG().
		SET upfgOutput[0]["tb"] TO tb.
		SET usc_convergeFlags TO LIST().
		SET usc_lastGoodVector TO V(1,0,0).
		SET upfgConverged TO FALSE.
		pushUIMessage( "UPFG reset", 5, PRIORITY_CRITICAL ).
	}
	
	//	Expects global variables "upfgConverged" and "stagingInProgress" as bool, "steeringVector" as vector and 
	//	"upfgConvergenceCriterion" and "upfgGoodSolutionCriterion" as scalars.
	//	Owns global variables "usc_lastGoodVector" as vector, "usc_convergeFlags" as list, "usc_stagingNoticed" as bool and 
	//	"usc_lastIterationTime" as scalar.
	DECLARE PARAMETER vehicle.		//	Expects a list of lexicon
	DECLARE PARAMETER upfgStage.	//	Expects a scalar
	DECLARE PARAMETER upfgTarget.	//	Expects a lexicon
	DECLARE PARAMETER upfgState.	//	Expects a lexicon
	DECLARE PARAMETER upfgInternal.	//	Expects a lexicon
	
	//	First run marked by undefined globals
	IF NOT (DEFINED usc_lastGoodVector) {
		GLOBAL usc_lastGoodVector IS V(1,0,0).
		GLOBAL usc_convergeFlags IS LIST().
		GLOBAL usc_stagingNoticed IS FALSE.
		GLOBAL usc_lastIterationTime IS upfgState["time"].
	}
	
	//	Run UPFG
	LOCAL currentIterationTime IS upfgState["time"].
	LOCAL lastTgo IS upfgInternal["tgo"].
	LOCAL currentVehicle IS vehicle:SUBLIST(upfgStage,vehicle:LENGTH-upfgStage).
	LOCAL upfgOutput IS upfg(currentVehicle, upfgTarget, upfgState, upfgInternal).
	
	//	Convergence check. The rule is that time-to-go as calculated between iterations
	//	should not change significantly more than the time difference between those iterations.
	//	Uses upfgState as timestamp, for equal grounds for comparison.
	//	Requires (a hardcoded) number of consecutive good values before calling it a convergence.
	LOCAL iterationDeltaTime IS currentIterationTime - usc_lastIterationTime.
	IF stagingInProgress {
		//	If the stage hasn't yet been activated, then we're doing a pre-flight convergence.
		//	That means that time effectively doesn't pass for the algorithm - so neither the
		//	iteration takes any time, nor any fuel (measured with remaining time of burn) is
		//	deducted from the stage.
		SET iterationDeltaTime TO 0.
		SET upfgOutput[0]["tb"] TO 0.
	}
	SET usc_lastIterationTime TO currentIterationTime.
	LOCAL expectedTgo IS lastTgo - iterationDeltaTime.
	SET lastTgo TO upfgOutput[1]["tgo"].
	IF ABS(expectedTgo-upfgOutput[1]["tgo"]) < upfgConvergenceCriterion {
		IF usc_lastGoodVector <> V(1,0,0) {
			IF VANG(upfgOutput[1]["vector"], usc_lastGoodVector) < upfgGoodSolutionCriterion {
				usc_convergeFlags:ADD(TRUE).
			} ELSE {
				IF NOT stagingInProgress {
					resetUPFG().
				}
			}
		} ELSE {
			usc_convergeFlags:ADD(TRUE).
		}
	} ELSE { SET usc_convergeFlags TO LIST(). }
	//	If we have enough number of consecutive good results - we're converged.
	IF usc_convergeFlags:LENGTH = 2 {
		SET upfgConverged TO TRUE.
		SET usc_convergeFlags TO LIST(TRUE, TRUE).
	}
	//	Check if we can steer
	IF upfgConverged AND NOT stagingInProgress {
		SET steeringVector TO LOOKDIRUP(vecYZ(upfgOutput[1]["vector"]), getRollVector(rollAngle)).
		SET usc_lastGoodVector TO upfgOutput[1]["vector"].
	}
	RETURN upfgOutput[0].
}

//	Throttle controller
FUNCTION throttleControl {
	//	Expects global variables "vehicle" as list, "upfgStage" as scalar, "throttleSetting" as scalar and "stagingInProgress" as bool.
	
	//	If we're guiding a stage nominally, it's simple. But if the stage is about to change into the next one,
	//	value of "upfgStage" is already incremented. In this case we shouldn't use the next stage values (this
	//	would ruin constant-acceleration stages).
	LOCAL whichStage IS upfgStage.
	IF stagingInProgress {
		SET whichStage TO upfgStage - 1.
	}
	
	IF vehicle[whichStage]["mode"] = 1 {
		SET throttleSetting TO vehicle[whichStage]["throttle"].
	}
	ELSE IF vehicle[whichStage]["mode"] = 2 {
		LOCAL currentThrust_ IS getThrust(vehicle[whichStage]["engines"]).
		LOCAL currentThrust IS currentThrust_[0].
		SET throttleSetting TO vehicle[whichStage]["throttle"]*(SHIP:MASS*1000*vehicle[whichStage]["gLim"]*g0) / (currentThrust).
	}
	ELSE { pushUIMessage( "throttleControl stage error (stage=" + upfgStage + "(" + whichStage + "), mode=" + vehicle[whichStage]["mode"] + ")!", 5, PRIORITY_CRITICAL ). }.
}.
