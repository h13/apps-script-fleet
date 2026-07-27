import { getGreeting } from './greeting.js';
import { setScriptProperties } from './setProperties.js';

function doGet(): GoogleAppsScript.HTML.HtmlOutput {
  return HtmlService.createHtmlOutputFromFile('app')
    .setTitle('Apps Script Web App')
    .setXFrameOptionsMode(HtmlService.XFrameOptionsMode.ALLOWALL);
}

function getMessage(): string {
  return getGreeting();
}
