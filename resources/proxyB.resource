*** Settings ***
Documentation    Browser und RequestsLibrary explizit über Proxy B (localhost:3129).
...              Mit ${PROXY_USER}/${PROXY_PASS} (per -v gesetzt) authentifizieren sich beide am Proxy:
...              der Browser über username/password, requests über die Zugangsdaten in der Proxy-URL.
Library          Browser
Library          Collections
Library          RequestsLibrary


*** Variables ***
${PROXY_USER}    ${EMPTY}
${PROXY_PASS}    ${EMPTY}


*** Keywords ***
Open Scenario Browser
    &{proxy}=    Create Dictionary    server=http://localhost:3129    bypass=localhost,127.0.0.1
    IF    $PROXY_USER
        Set To Dictionary    ${proxy}    username=${PROXY_USER}    password=${PROXY_PASS}
    END
    New Browser    chromium    headless=True    proxy=${proxy}
    New Context    ignoreHTTPSErrors=True

Scenario GET
    [Arguments]    ${url}
    ${server}=    Set Variable    http://localhost:3129
    IF    $PROXY_USER
        ${server}=    Set Variable    http://${PROXY_USER}:${PROXY_PASS}@localhost:3129
    END
    &{proxies}=    Create Dictionary    http=${server}    https=${server}
    GET    url=${url}    proxies=${proxies}    expected_status=200
