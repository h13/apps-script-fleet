import { getGreeting } from "./greeting.js";

function doGet(): GoogleAppsScript.HTML.HtmlOutput {
  return HtmlService.createHtmlOutputFromFile("app")
    .setTitle("GAS Web App")
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

function getMessage(): string {
  return getGreeting();
}
