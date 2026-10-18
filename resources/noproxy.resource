*** Settings ***
Documentation    Kein expliziter Proxy: weder Browser (New Browser) noch RequestsLibrary (GET) bekommen einen.
Library          Browser
Library          RequestsLibrary


*** Keywords ***
Open Scenario Browser
    New Browser    chromium    headless=True
    New Context    ignoreHTTPSErrors=True

Scenario GET
    [Arguments]    ${url}
    GET    url=${url}    expected_status=200
