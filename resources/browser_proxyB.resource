*** Settings ***
Documentation    Browser explizit über Proxy B (localhost:3129).
...              Mit ${PROXY_USER}/${PROXY_PASS} (per -v gesetzt) authentifiziert sich der Browser am Proxy.
Library          Browser
Library          Collections


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
