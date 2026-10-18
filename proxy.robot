*** Settings ***
Documentation    Welchen Proxy nutzen RequestsLibrary und Browser Library?
...              Proxy-Konfiguration von Browser und RequestsLibrary kommt aus ${SCENARIO_RESOURCE} (per -v gesetzt).
Library          OperatingSystem
Resource         ${SCENARIO_RESOURCE}

Suite Teardown    Close Browser    ALL


*** Variables ***
${SCENARIO_RESOURCE}    resources/noproxy.resource


*** Test Cases ***
Proxy Environment Variables
    [Documentation]    Zeigt, welche Proxy-Variablen rcc in die Umgebung des Tests setzt.
    FOR    ${name}    IN    HTTP_PROXY    HTTPS_PROXY    NO_PROXY    http_proxy    https_proxy    no_proxy
        ${value}=    Get Environment Variable    ${name}    <nicht gesetzt>
        Log To Console    ${name}=${value}
        Log    ${name}=${value}
    END

Python Request
    [Documentation]    RequestsLibrary: ohne proxies= wertet requests HTTP(S)_PROXY/NO_PROXY aus,
    ...    mit proxies= (${SCENARIO_RESOURCE}) gilt der explizite Proxy.
    Scenario GET    http://example.com/?via=python-requests

Open HTTP And HTTPS Page
    Open Scenario Browser
    New Page    http://example.com
    Get Title    ==    Example Domain
    Go To    https://example.org
    Get Title    ==    Example Domain
