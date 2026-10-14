*** Settings ***
Documentation    Browser OHNE explizite Proxy-Konfiguration.
Library          Browser


*** Keywords ***
Open Scenario Browser
    New Browser    chromium    headless=True
    New Context    ignoreHTTPSErrors=True
