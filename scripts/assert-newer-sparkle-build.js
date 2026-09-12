#!/usr/bin/env node

"use strict";

const fs = require("node:fs");
const maximumBuildComponent = 9_223_372_036_854_775_807n;

function buildParts(build) {
  if (typeof build !== "string" || !/^\d+(?:\.\d+)*$/.test(build)) {
    throw new Error("Build must contain only numeric components");
  }
  const parts = build.split(".").map(BigInt);
  if (parts.some((part) => part > maximumBuildComponent)) {
    throw new Error("Build components must fit Sparkle's signed 64-bit comparison");
  }
  return parts;
}

function buildFromAppcast(xml) {
  const match = /<sparkle:version>\s*([0-9]+(?:\.[0-9]+)*)\s*<\/sparkle:version>/.exec(xml);
  if (!match) throw new Error("Appcast is missing a numeric sparkle:version");
  return match[1];
}

function releaseURLFromAppcast(xml) {
  const match = /<link>\s*(https:\/\/github\.com\/negentropi\/roma-just-talk\/releases\/tag\/[^<\s]+)\s*<\/link>/.exec(xml);
  if (!match) throw new Error("Appcast is missing its Roma release URL");
  return match[1];
}

function compareBuilds(left, right) {
  const leftParts = buildParts(left);
  const rightParts = buildParts(right);
  const count = Math.max(leftParts.length, rightParts.length);
  for (let index = 0; index < count; index += 1) {
    const leftPart = leftParts[index] ?? 0n;
    const rightPart = rightParts[index] ?? 0n;
    if (leftPart !== rightPart) return leftPart > rightPart ? 1 : -1;
  }
  return 0;
}

function assertBuildAdvance(candidateXML, baselineXMLs, allowEqual = false) {
  const candidate = buildFromAppcast(candidateXML);
  buildParts(candidate);
  for (const baselineXML of baselineXMLs) {
    const baseline = buildFromAppcast(baselineXML);
    const comparison = compareBuilds(candidate, baseline);
    if (comparison < 0 || (!allowEqual && comparison === 0)) {
      const relation = allowEqual ? "not older than" : "newer than";
      throw new Error(`Candidate build ${candidate} must be ${relation} served build ${baseline}`);
    }
  }
  return candidate;
}

function assertNewerBuild(candidateXML, baselineXMLs) {
  return assertBuildAdvance(candidateXML, baselineXMLs);
}

function assertBuildNotOlder(candidateXML, baselineXMLs) {
  return assertBuildAdvance(candidateXML, baselineXMLs, true);
}

function assertNewerOrSameRelease(candidateXML, baselineXMLs) {
  const candidateReleaseURL = releaseURLFromAppcast(candidateXML);
  const candidate = buildFromAppcast(candidateXML);
  buildParts(candidate);
  for (const baselineXML of baselineXMLs) {
    const baseline = buildFromAppcast(baselineXML);
    const sameRelease = releaseURLFromAppcast(baselineXML) === candidateReleaseURL;
    const comparison = compareBuilds(candidate, baseline);
    if (comparison < 0 || (!sameRelease && comparison === 0)) {
      throw new Error(`Candidate build ${candidate} must advance served build ${baseline}`);
    }
  }
  return candidate;
}

if (require.main === module) {
  try {
    const arguments_ = process.argv.slice(2);
    const allowEqual = arguments_[0] === "--allow-equal";
    const allowSameRelease = arguments_[0] === "--allow-same-release";
    const [candidatePath, ...baselinePaths] = allowEqual || allowSameRelease
      ? arguments_.slice(1)
      : arguments_;
    if (!candidatePath) throw new Error("Pass a candidate appcast and optional served appcasts");
    const candidate = fs.readFileSync(candidatePath, "utf8");
    const baselines = baselinePaths.map((path) => fs.readFileSync(path, "utf8"));
    const build = allowSameRelease
      ? assertNewerOrSameRelease(candidate, baselines)
      : assertBuildAdvance(candidate, baselines, allowEqual);
    process.stdout.write(`${build}\n`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

module.exports = {
  assertBuildNotOlder,
  assertNewerBuild,
  assertNewerOrSameRelease,
  buildFromAppcast,
  buildParts,
  compareBuilds,
  releaseURLFromAppcast,
};
