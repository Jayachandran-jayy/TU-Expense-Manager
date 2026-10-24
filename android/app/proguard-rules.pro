# ProGuard rules for llama_flutter_android
-keep class com.write4me.llama_flutter_android.** { *; }
-keep class kotlin.jvm.functions.Function1
-keepclassmembers class * implements kotlin.jvm.functions.Function1 {
    public java.lang.Object invoke(java.lang.Object);
}
-keepclasseswithmembernames class * {
    native <methods>;
}

# pdfbox-android: optional JPEG 2000 decoder is not bundled
-dontwarn com.gemalto.jp2.JP2Decoder
