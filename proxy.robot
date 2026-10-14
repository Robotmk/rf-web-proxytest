*** Settings ***
Documentation    Welcher Proxy wird vom Browser genutzt?
...              Die Browser-Konfiguration kommt aus ${BROWSER_RESOURCE} (per -v gesetzt).
Library          OperatingSystem
Resource         ${BROWSER_RESOURCE}

Suite Teardown    Close Browser    ALL


*** Variables ***
${BROWSER_RESOURCE}    resources/browser_noproxy.resource


*** Test Cases ***
Proxy Environment Variables
    [Documentation]    Zeigt, welche Proxy-Variablen rcc in die Umgebung des Tests setzt.
    FOR    ${name}    IN    HTTP_PROXY    HTTPS_PROXY    NO_PROXY    http_proxy    https_proxy    no_proxy
        ${value}=    Get Environment Variable    ${name}    <nicht gesetzt>
        Log To Console    ${name}=${value}
        Log    ${name}=${value}
    END

Python Request (Kontrolle)
    [Documentation]    Positivkontrolle: Python (urllib) wertet HTTP(S)_PROXY aus.
    ...    Taucht dieser Request in Proxy A auf, ist das RCC-Proxyprofil im Prozess wirksam.
    ${status}=    Evaluate    urllib.request.urlopen("http://example.com/?via=python-urllib").status    modules=urllib.request
    Should Be Equal As Integers    ${status}    200

Open HTTP And HTTPS Page
    Open Scenario Browser
    New Page    http://example.com
    Get Title    ==    Example Domain
    Go To    https://example.org
    Get Title    ==    Example Domain
