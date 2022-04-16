rd /s /q release
mkdir release
cat robo2.p8 | sed "s/--.*//g" | sed "/^[ ]*$/d" | sed "s/^[ ]*//g" > robo_release.p8
pushd release
"c:\program files (x86)\pico-8\pico8.exe" -export "robo.html" ..\robo_release.p8
ren robo.html index.html
zip robo.zip index.html robo.js
"c:\program files (x86)\pico-8\pico8.exe" -export "robo.p8.png" ..\robo_release.p8
popd
del robo_release.p8
