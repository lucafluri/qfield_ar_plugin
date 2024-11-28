@echo off

REM Define the source directory and the output zip file
set SOURCE_DIR=qfield-3d-nav
set OUTPUT_ZIP=qfield-3d-nav.zip

REM Remove the existing zip file if it exists
del /f %OUTPUT_ZIP%

REM Create a new zip file from the source directory
powershell -command "Compress-Archive -Path %SOURCE_DIR%\* -DestinationPath %OUTPUT_ZIP%"

echo Zip operation completed successfully.
