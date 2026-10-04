package opensource.jenny;

public final class Jni {
    static { System.load(System.getProperty("jasmine.lib")); }
    public static native void init(String path);
    public static native String invoke(String params);
}
