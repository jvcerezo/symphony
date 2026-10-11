# youtubedl-android maps yt-dlp JSON with Jackson (reflection) and ships no
# consumer rules of its own.
-keep class com.yausername.** { *; }
-keep class com.fasterxml.jackson.databind.** { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-dontwarn com.fasterxml.jackson.databind.ext.**
-dontwarn java.beans.**
