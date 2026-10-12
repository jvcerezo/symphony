# youtubedl-android maps yt-dlp JSON with Jackson (reflection) and ships no
# consumer rules of its own.
-keep class com.yausername.** { *; }
-keep class com.fasterxml.jackson.databind.** { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-dontwarn com.fasterxml.jackson.databind.ext.**
-dontwarn java.beans.**

# It unpacks its bundled Python with Commons Compress, which builds zip
# extra-field classes by reflection; stripped, init fails with
# "class ... is not a concrete class" and yt-dlp never starts.
-keep class org.apache.commons.compress.archivers.zip.** { *; }
