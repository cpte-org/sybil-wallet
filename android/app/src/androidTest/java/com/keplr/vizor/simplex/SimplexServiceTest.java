package com.keplr.vizor.simplex;

import android.app.Instrumentation;
import android.content.*;
import android.os.*;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.runner.AndroidJUnit4;
import org.json.*;
import org.junit.Test;
import org.junit.runner.RunWith;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import java.util.concurrent.*;
import static org.junit.Assert.*;

/** Real IPC/native execution; Java keeps test-only Kotlin runtime out of R8 assumptions. */
@RunWith(AndroidJUnit4.class)
public class SimplexServiceTest {
    private static final String DESCRIPTOR = "com.keplr.vizor.simplex.private.v1";
    private static final int ATTACH = 1, OPEN = 2, COMMAND = 3, POLL = 4, STOP = 5;
    private static final String CREATE = "/_create user {\"profile\":{\"displayName\":\"NativeTest\",\"fullName\":\"\"},\"pastTimestamp\":false,\"userChatRelay\":false,\"clientService\":false}";
    private final Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
    private Context context() { return instrumentation.getTargetContext(); }
    private interface Write { void write(Parcel parcel); }
    private static class Bound {
        IBinder binder;
        ServiceConnection connection;
        final String id = UUID.randomUUID().toString();
        final Binder owner = new Binder();
    }
    private Bound bind() throws Exception {
        CountDownLatch connected = new CountDownLatch(1);
        Bound bound = new Bound();
        bound.connection = new ServiceConnection() {
            public void onServiceConnected(ComponentName name, IBinder service) { bound.binder = service; connected.countDown(); }
            public void onServiceDisconnected(ComponentName name) {}
        };
        Intent intent = new Intent().setClassName(context(), "com.keplr.vizor.simplex.SimplexService");
        assertTrue(context().bindService(intent, bound.connection, Context.BIND_AUTO_CREATE));
        assertTrue(connected.await(15, TimeUnit.SECONDS));
        request(bound, ATTACH, p -> p.writeStrongBinder(bound.owner));
        return bound;
    }
    private String request(Bound s, int code, Write write) throws Exception {
        Parcel data = Parcel.obtain(), reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(DESCRIPTOR); data.writeString(s.id); write.write(data);
            assertTrue(s.binder.transact(code, data, reply, 0)); reply.readException();
            return code == ATTACH ? "" : new String(reply.createByteArray(), StandardCharsets.UTF_8);
        } finally { data.recycle(); reply.recycle(); }
    }
    private String open(Bound s, String path, String key) throws Exception {
        return request(s, OPEN, p -> { p.writeString(path); p.writeString(key); });
    }
    private JSONObject command(Bound s, String text) throws Exception {
        JSONObject raw = new JSONObject(request(s, COMMAND, p -> p.writeString(text)));
        assertFalse("Native test command failed", raw.has("error"));
        return raw.getJSONObject("result");
    }
    private void close(Bound s) throws Exception {
        CountDownLatch dead = new CountDownLatch(1);
        s.binder.linkToDeath(dead::countDown, 0);
        context().unbindService(s.connection);
        Parcel data = Parcel.obtain();
        try {
            data.writeInterfaceToken(DESCRIPTOR); data.writeString(s.id);
            try { s.binder.transact(STOP, data, null, IBinder.FLAG_ONEWAY); } catch (RemoteException ignored) {}
            assertTrue("Native process must die before reopen", dead.await(10, TimeUnit.SECONDS));
        } finally { data.recycle(); }
    }
    private File directory(String label) {
        File result = new File(context().getCacheDir(), "simplex-" + label + "-" + UUID.randomUUID());
        assertTrue(result.mkdirs());
        return result;
    }
    private void remove(File file) {
        File[] children = file.listFiles();
        if (children != null) for (File child : children) remove(child);
        file.delete();
    }
    @Test public void testEncryptedOpenProcessDeathAndReopen() throws Exception {
        File directory = directory("encrypted");
        String path = new File(directory, "chat").getPath(), key = UUID.randomUUID().toString();
        try {
            Bound first = bind();
            try {
                assertEquals("ok", new JSONObject(open(first, path, key)).getString("type"));
                assertEquals("activeUser", command(first, CREATE).getString("type"));
            } finally { close(first); }
            File database = new File(path + "_chat.db");
            assertTrue(database.isFile());
            byte[] header = new byte[16];
            try (InputStream input = new FileInputStream(database)) { assertEquals(16, input.read(header)); }
            assertFalse(new String(header, StandardCharsets.UTF_8).startsWith("SQLite format 3"));
            Bound wrong = bind();
            try { assertNotEquals("ok", new JSONObject(open(wrong, path, UUID.randomUUID().toString())).getString("type")); }
            finally { close(wrong); }
            Bound second = bind();
            try {
                assertEquals("ok", new JSONObject(open(second, path, key)).getString("type"));
                assertTrue(command(second, "/u").toString().contains("NativeTest"));
            } finally { close(second); }
        } finally { remove(directory); }
    }
    @Test public void testNativeRelayExchange() throws Exception {
        String invitation = InstrumentationRegistry.getArguments().getString("simplexInvitation");
        org.junit.Assume.assumeNotNull(invitation);
        assertTrue(invitation.startsWith("simplex:/invitation#") && invitation.length() <= 16384 && !invitation.matches(".*\\s.*"));
        File directory = directory("relay");
        String path = new File(directory, "chat").getPath(), key = UUID.randomUUID().toString();
        Bound s = null;
        try {
            s = bind();
            assertEquals("ok", new JSONObject(open(s, path, key)).getString("type"));
            command(s, CREATE);
            command(s, "/network socks=off smp-proxy=always smp-proxy-fallback=no");
            command(s, "/_start");
            command(s, "/connect " + invitation);
            int contact = 0;
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(90);
            while (contact == 0 && System.nanoTime() < deadline) {
                String event = request(s, POLL, p -> {});
                if (!event.isEmpty()) {
                    JSONObject result = new JSONObject(event).optJSONObject("result");
                    if (result != null && result.optString("type").equals("contactConnected")) contact = result.getJSONObject("contact").getInt("contactId");
                }
                Thread.sleep(100);
            }
            assertTrue("Disposable peer must connect", contact > 0);
            String code = command(s, "/_get code @" + contact).getString("connectionCode").replace(" ", "");
            Bundle status = new Bundle(); status.putString("simplexSecurityCode", code); instrumentation.sendStatus(0, status);
            String envelope = new JSONObject().put("domain", "zcash-contact/transport").put("network", "regtest")
                .put("id", "AAAAAAAAAAAAAAAAAAAAAAAA").put("packet", "SIGIL ANDROID DISPOSABLE TRANSPORT TEST").toString();
            JSONArray messages = new JSONArray().put(new JSONObject().put("msgContent", new JSONObject().put("type", "text").put("text", envelope)));
            assertEquals("newChatItems", command(s, "/_send @" + contact + " json " + messages).getString("type"));
            boolean received = false;
            deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(90);
            while (!received && System.nanoTime() < deadline) {
                received = request(s, POLL, p -> {}).contains("SIGIL LINUX DISPOSABLE TRANSPORT REPLY");
                Thread.sleep(100);
            }
            assertTrue("Linux test reply received", received);
            close(s); s = null;
            s = bind();
            assertEquals("ok", new JSONObject(open(s, path, key)).getString("type"));
            // Match the shared adapter: restoring a controller initially opens
            // maintenance mode; history commands require the active chat runtime.
            assertEquals("activeUser", command(s, "/u").getString("type"));
            command(s, "/network socks=off smp-proxy=always smp-proxy-fallback=no");
            command(s, "/_start");
            assertTrue("Reply survives native death", command(s, "/_get chat @" + contact + " count=100").toString().contains("SIGIL LINUX DISPOSABLE TRANSPORT REPLY"));
            Bundle persisted = new Bundle(); persisted.putBoolean("simplexDurableReply", true); instrumentation.sendStatus(0, persisted);
        } finally { if (s != null) close(s); remove(directory); }
    }
    @Test public void testStaleStopCannotKillActiveSession() throws Exception {
        Bound s = bind();
        try {
            Parcel data = Parcel.obtain();
            try { data.writeInterfaceToken(DESCRIPTOR); data.writeString("stale-session"); s.binder.transact(STOP, data, null, IBinder.FLAG_ONEWAY); }
            finally { data.recycle(); }
            Thread.sleep(100); assertTrue(s.binder.isBinderAlive());
        } finally { close(s); }
    }
    @Test public void testCloseDuringNativeOpen() throws Exception {
        File directory = directory("open-race");
        Bound s = bind();
        CountDownLatch entered = new CountDownLatch(1), finished = new CountDownLatch(1);
        Thread worker = new Thread(() -> {
            entered.countDown();
            try { open(s, new File(directory, "chat").getPath(), UUID.randomUUID().toString()); } catch (Throwable ignored) {}
            finally { finished.countDown(); }
        });
        try {
            worker.start(); assertTrue(entered.await(5, TimeUnit.SECONDS)); close(s);
            assertTrue("Open ends with process death", finished.await(10, TimeUnit.SECONDS));
        } finally { remove(directory); }
    }
    @Test public void testNativeCoreNeverLoadsInWalletProcess() throws Exception {
        try (BufferedReader input = new BufferedReader(new FileReader("/proc/self/maps"))) {
            String line;
            while ((line = input.readLine()) != null) assertFalse(line.contains("libsimplex.so"));
        }
    }
    @Test public void testUnbindTerminatesProcess() throws Exception {
        Bound s = bind(); CountDownLatch dead = new CountDownLatch(1);
        s.binder.linkToDeath(dead::countDown, 0); context().unbindService(s.connection);
        assertTrue(dead.await(10, TimeUnit.SECONDS));
    }
}
