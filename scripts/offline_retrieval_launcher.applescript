set bundlePath to POSIX path of (path to me)
set pagePath to bundlePath & "Contents/Resources/app/index.html"
tell application "Finder" to open POSIX file pagePath
