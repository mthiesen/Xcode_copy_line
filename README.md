Xcode_copy_line
===============

### Description

Many source editors allow users to copy/cut the current line by using the shortcuts `⌘C` and `⌘X` while there is no selected text. If a line that was copied in such a way is pasted, it is inserted directly above the current line without moving the cursor. This is very useful while restructuring code and all but eliminates the need to memorize additional shortcuts for transposing lines.

Sublime Text and Visual Studio offer such a behaviour. This plug-in implements this behaviour in Xcode.

### Installation

Download and compile the project (the plugin will be installed during the build process) or download the [binary](https://github.com/mthiesen/Xcode_copy_line/releases/download/v1.5/Xcode_copy_line.xcplugin.zip) and unzip it to `~/Library/Application Support/Developer/Shared/Xcode/Plug-ins/`

### Compatibility

The plug-in is compatible with Xcode 5, Xcode 5.1, Xcode 6, Xcode 6.1, Xcode 6.2 and Xcode 6.3.

### Thanks

* [insanehunter](https://github.com/insanehunter) and his [XCode4_beginning_of_line](https://github.com/insanehunter/XCode4_beginning_of_line) project which served as an inspiration
* [creaceed.com](http://www.creaceed.com) and the [Mercurial Xcode Plugin](https://bitbucket.org/creaceed/mercurial-xcode-plugin) which I based the project layout on
