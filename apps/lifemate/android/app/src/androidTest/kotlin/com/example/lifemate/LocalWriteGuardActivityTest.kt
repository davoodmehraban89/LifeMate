package com.example.lifemate

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.util.UUID
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LocalWriteGuardActivityTest {
    private fun engine(activity: MainActivity): FlutterEngine {
        // Observe embedding lifetime without adding a production test hook.
        val getter = FlutterActivity::class.java.getDeclaredMethod("getFlutterEngine")
        getter.isAccessible = true
        return getter.invoke(activity) as FlutterEngine
    }

    @Test
    fun pendingNativeWriteSurvivesActivityAndEngineRecreation() {
        assertFalse(LocalWriteGuard.getBlocked())
        val token = LocalWriteGuard.beginWrite()
        assertNotNull(token)
        try {
            ActivityScenario.launch(MainActivity::class.java).use { scenario ->
                lateinit var firstActivity: MainActivity
                lateinit var firstEngine: FlutterEngine
                var firstEngineDestroyed = false
                scenario.onActivity { activity ->
                    firstActivity = activity
                    firstEngine = engine(activity)
                    firstEngine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
                        override fun onPreEngineRestart() {}
                        override fun onEngineWillDestroy() {
                            firstEngineDestroyed = true
                        }
                    })
                    assertTrue(activity.shouldDestroyEngineWithHost())
                    assertTrue(LocalWriteGuard.getBlocked())
                }
                scenario.recreate()
                scenario.onActivity { activity ->
                    assertNotSame(firstActivity, activity)
                    assertTrue(firstActivity.isDestroyed)
                    assertTrue(firstEngineDestroyed)
                    assertNotSame(firstEngine, engine(activity))
                    assertTrue(LocalWriteGuard.getBlocked())
                    assertNull(LocalWriteGuard.beginWrite())
                    assertFalse(LocalWriteGuard.completeWrite(UUID.randomUUID().toString()))
                    assertTrue(LocalWriteGuard.getBlocked())
                }
            }
        } finally {
            // This test owns only a synthetic marker, not any DataStore I/O.
            assertTrue(LocalWriteGuard.completeWrite(requireNotNull(token)))
        }
        assertFalse(LocalWriteGuard.getBlocked())
    }
}
