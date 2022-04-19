rd /s /q release
mkdir release

pandoc --from markdown-auto_identifiers+fenced_divs+link_attributes --self-contained --ascii -t html4 --css robo_manual.css robo_manual.md -o release\robo_manual.html
REM pandoc --from markdown-auto_identifiers+fenced_divs+link_attributes --ascii -t pdf robo_manual.md -o release\robo_manual.pdf

cat robo2.p8 | sed "s/--.*//g" | sed "/^[ ]*$/d" | sed "s/^[ ]*//g" > robo_release.p8
pushd release

"c:\program files (x86)\pico-8\pico8.exe" -export "robo.html" ..\robo_release.p8
ren robo.html index.html
zip robo_web.zip index.html robo.js

"c:\program files (x86)\pico-8\pico8.exe" -export "robo.p8.png" ..\robo_release.p8

"c:\program files (x86)\pico-8\pico8.exe" -export "-i 1 -s 2 -c 12 robo.bin" ..\robo_release.p8

popd
del robo_release.p8

butler push release\robo_web.zip decarabas/robot-garden:html-universal --if-changed
butler push release\robo.bin\robo_windows.zip decarabas/robot-garden:windows-stable --if-changed
butler push release\robo.bin\robo_linux.zip decarabas/robot-garden:linux-stable --if-changed
butler push release\robo.bin\robo_osx.zip decarabas/robot-garden:osx-stable --if-changed
