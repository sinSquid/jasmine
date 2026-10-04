import java.io.File;
import opensource.jenny.Jni;
import org.json.JSONObject;

public final class DownloadProbe {
    private static native int flag(String library);

    private static String call(String method, String params) throws Exception {
        JSONObject request = new JSONObject();
        request.put("method", method);
        request.put("params", params);
        JSONObject response = new JSONObject(Jni.invoke(request.toString()));
        if (!response.optString("error_message").isEmpty()) {
            // Do not expose native response payloads or possible account fields.
            throw new IllegalStateException("Native method failed: " + method);
        }
        return response.getString("response_data");
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 4) throw new IllegalArgumentException("Expected four probe arguments");
        int requested = Integer.parseInt(args[3]);
        if (requested != 1 && requested != 2 && requested != 5) {
            throw new IllegalArgumentException("Unsupported probe count");
        }
        File state = new File(args[1]);
        if (state.exists() || !state.mkdirs()) {
            throw new IllegalStateException("The probe requires a fresh state directory");
        }
        System.setProperty("jasmine.lib", args[0]);
        System.load(args[2]);
        Jni.init(state.getAbsolutePath());
        // init_dart2 starts the downloader; this probe deliberately never calls it.
        call("init_dart", "");
        int before = flag(args[0]);
        call("set_download_thread", Integer.toString(requested));
        int after = flag(args[0]);
        int loaded = Integer.parseInt(call("load_download_thread", ""));
        JSONObject membership = new JSONObject(call("pro_info_all", ""));
        boolean membershipFalse = !membership.getJSONObject("pro_info_af").getBoolean("is_pro")
                && !membership.getJSONObject("pro_info_pat").getBoolean("is_pro");
        if ((before != -3 && before != 0) || after != 1
                || loaded != requested || !membershipFalse) {
            throw new AssertionError("Download restart probe failed");
        }
        JSONObject result = new JSONObject();
        result.put("requested", requested);
        result.put("loaded", loaded);
        result.put("flag_before", before);
        result.put("flag_after", after);
        result.put("membership_false", membershipFalse);
        System.out.println("JASMINE_RESTART_RESULT " + result.toString());
    }
}
