precision highp float;

attribute vec2 aCoord, bCoord, nextCoord, prevCoord;
attribute vec4 aColor, bColor;
attribute float lineEnd, lineTop;

uniform vec2 scale, translate, scaleRatio;
uniform float thickness, pixelRatio, id;
uniform vec4 viewport;
uniform float miterLimit, dashLength;

varying vec4 fragColor;
varying vec4 startCutoff, endCutoff;
varying vec2 tangent;
varying vec2 startCoord, endCoord;
varying float startMiter, endMiter;

const float MAX_LINES = 256.;
const float REVERSE_THRESHOLD = -.875;

//TODO: possible optimizations: avoid overcalculating all for vertices and calc just one instead
//TODO: precalculate dot products, normalize things etc.

float distToLine(vec2 p, vec2 a, vec2 b) {
	vec2 diff = b - a;
	vec2 perp = normalize(vec2(-diff.y, diff.x));
	return dot(p - a, perp);
}

void main() {
	vec2 aCoord = aCoord, bCoord = bCoord, prevCoord = prevCoord, nextCoord = nextCoord;
	vec2 normalWidth = thickness / scaleRatio;

	float lineStart = 1. - lineEnd;
	float lineBot = 1. - lineTop;
	float depth = (MAX_LINES - 1. - id) / (MAX_LINES);

	fragColor = (lineEnd * bColor + lineStart * aColor) / 255.;

	vec2 prevDiff = aCoord - prevCoord;
	vec2 currDiff = bCoord - aCoord;
	vec2 nextDiff = nextCoord - bCoord;

	vec2 prevDirection = normalize(prevDiff);
	vec2 currDirection = normalize(currDiff);
	vec2 nextDirection = normalize(nextDiff);

	vec2 prevTangent = normalize(prevDiff * scaleRatio);
	vec2 currTangent = normalize(currDiff * scaleRatio);
	vec2 nextTangent = normalize(nextDiff * scaleRatio);

	vec2 prevNormal = vec2(-prevTangent.y, prevTangent.x);
	vec2 currNormal = vec2(-currTangent.y, currTangent.x);
	vec2 nextNormal = vec2(-nextTangent.y, nextTangent.x);

	vec2 startJoinNormal = normalize(prevTangent - currTangent);
	vec2 endJoinNormal = normalize(currTangent - nextTangent);

	//collapsed/unidirectional segment cases
	if (prevDirection == currDirection) {
		startJoinNormal = currNormal;
	}
	if (nextDirection == currDirection) {
		endJoinNormal = currNormal;
	}
	if (prevCoord == aCoord) {
		startJoinNormal = currNormal;
		prevTangent = currTangent;
		prevNormal = currNormal;
	}
	if (aCoord == bCoord) {
		endJoinNormal = startJoinNormal;
		currNormal = prevNormal;
		currTangent = prevTangent;
	}
	if (bCoord == nextCoord) {
		endJoinNormal = currNormal;
		nextTangent = currTangent;
		nextNormal = currNormal;
	}

	tangent = currTangent;

	//calculate join shifts relative to normals
	float startJoinShift = dot(currNormal, startJoinNormal);
	float endJoinShift = dot(currNormal, endJoinNormal);

	float startMiterRatio = abs(1. / startJoinShift);
	float endMiterRatio = abs(1. / endJoinShift);

	vec2 startJoin = startJoinNormal * startMiterRatio;
	vec2 endJoin = endJoinNormal * endMiterRatio;

	vec2 startTopJoin, startBotJoin, endTopJoin, endBotJoin;
	startTopJoin = sign(startJoinShift) * startJoin * .5;
	startBotJoin = -startTopJoin;

	endTopJoin = sign(endJoinShift) * endJoin * .5;
	endBotJoin = -endTopJoin;

	vec4 miterWidth = vec4(startJoinNormal, endJoinNormal) * thickness * miterLimit * .5;

	vec2 aTopCoord = aCoord + normalWidth * startTopJoin;
	vec2 bTopCoord = bCoord + normalWidth * endTopJoin;
	vec2 aBotCoord = aCoord + normalWidth * startBotJoin;
	vec2 bBotCoord = bCoord + normalWidth * endBotJoin;

	//miter anti-clipping
	float baClipping = distToLine(bCoord, aCoord, aBotCoord) / dot(normalize(normalWidth * endBotJoin), normalize(normalWidth.yx * vec2(-startBotJoin.y, startBotJoin.x)));
	float abClipping = distToLine(aCoord, bCoord, bTopCoord) / dot(normalize(normalWidth * startBotJoin), normalize(normalWidth.yx * vec2(-endBotJoin.y, endBotJoin.x)));

	//prevent close to reverse direction switch
	bool prevReverse = dot(currTangent, prevTangent) <= REVERSE_THRESHOLD && abs(dot(currTangent, prevNormal)) * min(length(prevDiff), length(currDiff)) <  length(normalWidth * currNormal);
	bool nextReverse = dot(currTangent, nextTangent) <= REVERSE_THRESHOLD
		&& abs(dot(currTangent, nextNormal)) * min(length(nextDiff), length(currDiff)) <  length(normalWidth * currNormal);

	if (prevReverse) {
		//make join rectangular
		vec2 miterShift = normalWidth * startJoinNormal * miterLimit * .5;
		float normalAdjust = 1. - min(miterLimit / startMiterRatio, 1.);
		aBotCoord = aCoord + miterShift - normalAdjust * normalWidth * currNormal * .5;
		aTopCoord = aCoord + miterShift + normalAdjust * normalWidth * currNormal * .5;
	}
	else if (!nextReverse && baClipping > 0. && baClipping < length(normalWidth * endBotJoin)) {
		//handle miter clipping
		bTopCoord -= normalWidth * endTopJoin;
		bTopCoord += normalize(endTopJoin * normalWidth) * baClipping;
	}

	if (nextReverse) {
		//make join rectangular
		vec2 miterShift = normalWidth * endJoinNormal * miterLimit * .5;
		float normalAdjust = 1. - min(miterLimit / endMiterRatio, 1.);
		bBotCoord = bCoord + miterShift - normalAdjust * normalWidth * currNormal * .5;
		bTopCoord = bCoord + miterShift + normalAdjust * normalWidth * currNormal * .5;
	}
	else if (!prevReverse && abClipping > 0. && abClipping < length(normalWidth * startBotJoin)) {
		//handle miter clipping
		aBotCoord -= normalWidth * startBotJoin;
		aBotCoord += normalize(startBotJoin * normalWidth) * abClipping;
	}

	vec2 aTopPosition = (aTopCoord + translate) * scale;
	vec2 aBotPosition = (aBotCoord + translate) * scale;

	vec2 bTopPosition = (bTopCoord + translate) * scale;
	vec2 bBotPosition = (bBotCoord + translate) * scale;

	//position is normalized 0..1 coord on the screen
	vec2 position = (aTopPosition * lineTop + aBotPosition * lineBot) * lineStart + (bTopPosition * lineTop + bBotPosition * lineBot) * lineEnd;

	//bevel miter cutoffs
	startMiter = 0.;
	if (dot(currTangent, prevTangent) < .5) {
		startMiter = 1.;
		startCutoff = vec4(aCoord, aCoord);
		startCutoff.zw += (prevCoord == aCoord ? startBotJoin : vec2(-startJoin.y, startJoin.x)) / scaleRatio;
		startCutoff = (startCutoff + translate.xyxy) * scaleRatio.xyxy;
		startCutoff += viewport.xyxy;
		startCutoff += miterWidth.xyxy;
	}

	endMiter = 0.;
	if (dot(currTangent, nextTangent) < .5) {
		endMiter = 1.;
		endCutoff = vec4(bCoord, bCoord);
		endCutoff.zw += (nextCoord == bCoord ? endTopJoin :  vec2(-endJoinNormal.y, endJoinNormal.x))  / scaleRatio;
		endCutoff = (endCutoff + translate.xyxy) * scaleRatio.xyxy;
		endCutoff += viewport.xyxy;
		endCutoff += miterWidth.zwzw;
	}

	startCoord = (aCoord + translate) * scaleRatio + viewport.xy;
	endCoord = (bCoord + translate) * scaleRatio + viewport.xy;

	gl_Position = vec4(position  * 2.0 - 1.0, depth, 1);
}
