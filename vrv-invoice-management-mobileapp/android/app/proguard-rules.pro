############################################
## Flutter & App Base Rules
############################################
-keep class io.flutter.** { *; }
-keep class com.example.** { *; }    # Your app package
-keep class androidx.** { *; }

############################################
## Keep all classes with @Keep annotation
############################################
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

############################################
## JSON Serialization & Reflection
############################################
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

-keepattributes Signature
-keepattributes *Annotation*
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

############################################
## Native Methods
############################################
-keepclasseswithmembernames class * {
    native <methods>;
}

############################################
## Play Core Library (In-App Updates & Features)
############################################
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

-keep class com.google.android.play.core.appupdate.** { *; }
-dontwarn com.google.android.play.core.appupdate.**

############################################
## Common Flutter Plugins
############################################
-keep class com.baseflow.permissionhandler.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.tasks.** { *; }
-keep class androidx.core.content.** { *; }
-keep class info.android.deviceinfo.** { *; }
-keep class com.example.image_gallery_saver.** { *; }

############################################
## Prevent Flutter JNI/MethodChannel Breakage
############################################
-keepclassmembers class * {
    void onMethodCall(io.flutter.plugin.common.MethodCall, io.flutter.plugin.common.MethodChannel$Result);
}

############################################
## General Optimizations
############################################
-dontnote
-dontwarn org.jetbrains.annotations.**
-dontwarn kotlin.**
-dontwarn kotlin.jvm.**

# Keep entry points (Application, Activities, Services, BroadcastReceivers)
-keep class * extends android.app.Application { *; }
-keep class * extends android.app.Activity { *; }
-keep class * extends android.app.Service { *; }
-keep class * extends android.content.BroadcastReceiver { *; }
-keep class * extends android.content.ContentProvider { *; }
