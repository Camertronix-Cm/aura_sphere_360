# Phase 0: How to Research Before You Code (And Why It Saves You Days of Debugging)

**TL;DR:** We spent half a day reading source code before writing a single line of our Android WebRTC plugin. That research prevented 3+ days of debugging and architectural rewrites. Here's our Phase 0 framework and why you should adopt it.

---

## The Problem: Assumptions Are Expensive

Picture this: You're porting a Flutter plugin from iOS to Android. The iOS version uses a singleton pattern to access video tracks:

```objc
FlutterWebRTCPlugin *plugin = [FlutterWebRTCPlugin sharedSingleton];
RTCMediaStreamTrack *track = [plugin trackForId:trackId peerConnectionId:pcId];
```

You assume Android has the same API. You spend two days implementing, only to discover at runtime that `getInstance()` doesn't exist. Now you're debugging, refactoring, and questioning your life choices.

**This happened to us.** But it didn't cost us two days—it cost us half a day of research *before* we wrote any code.

Welcome to Phase 0.

---

## What Is Phase 0?

Phase 0 is deliberate, structured research conducted *before* implementation begins. It's not "reading the docs" (though that's part of it). It's a systematic verification of every assumption your implementation depends on.

Think of it as the software equivalent of "measure twice, cut once."

### Phase 0 vs. Traditional Planning

| Traditional Approach | Phase 0 Approach |
|---------------------|------------------|
| Read documentation | Read documentation **and source code** |
| Assume API parity | **Verify** API parity |
| Start coding, debug later | Verify first, code confidently |
| Hope for the best | **Document** what you found |
| 2-3 day debugging cycles | 0.5 day research, smooth implementation |

---

## Our Phase 0 Story: Porting a WebRTC Plugin

We were building a high-performance WebRTC pixel streaming plugin for Flutter. The iOS version was done and working beautifully. Android should be straightforward, right?

**Wrong.**

Here's what we needed to verify:

1. How do we access video tracks by ID?
2. Is the `VideoSink` interface available?
3. Does `YuvHelper` exist for frame conversion?
4. Where is the WebRTC AAR located?
5. What's the minimum SDK version?

Instead of assuming "it's probably the same as iOS," we spent half a day in the source code.

---

## The Phase 0 Framework: 5 Steps

### Step 1: Locate the Source

Don't just read docs—read the actual implementation.

For Flutter plugins, that means diving into your pub cache:

```bash
# Find the package
find ~/.pub-cache/hosted -name "flutter_webrtc-0.11.7" -type d

# Explore the Android source
cd ~/.pub-cache/hosted/pub.dev/flutter_webrtc-0.11.7/android
find . -name "*.java" -o -name "*.kt"
```

**Pro tip:** Use `grep` liberally. If you're looking for a method, search for it:

```bash
grep -r "getLocalVideoTrack\|getRemoteVideoTrack" android/src/
```

### Step 2: Verify Every API You'll Use

Create a checklist. For our WebRTC plugin, it looked like this:

```markdown
## API Verification Checklist

- [ ] Track registry API — how to get VideoTrack from track ID
- [ ] VideoSink interface — confirm org.webrtc.VideoSink exists
- [ ] VideoTrack.addSink() / removeSink() methods
- [ ] YuvHelper availability and methods
- [ ] WebRTC AAR location and version
- [ ] Minimum SDK requirements
```

Then systematically verify each item.

### Step 3: Document What You Find (Especially Surprises)

This is critical. Don't just verify—**write it down**.

We created a `PHASE_0_RESEARCH_FINDINGS.md` with 11 sections:

1. Track Registry API
2. VideoSink Interface
3. YuvHelper Availability
4. WebRTC AAR Location
5. Minimum SDK Requirements
6. Additional Findings
7. Critical Architectural Decision
8. Phase 0 Verification Checklist
9. Updated Implementation Strategy
10. Risk Assessment
11. Next Steps

The most valuable section? **"Critical Architectural Decision"**—where we documented that Android doesn't have a singleton pattern like iOS.

### Step 4: Identify Risks and Mitigation Strategies

Not everything will be perfect. Document the risks:

| Risk | Severity | Mitigation |
|------|----------|------------|
| No singleton track access | 🔴 High | Implement registry pattern |
| YuvHelper.I420ToABGR missing | 🟡 Medium | Fallback to libyuv Maven |
| Thread safety issues | 🟡 Medium | Use AtomicInteger, Handler |
| Build system complexity | 🟢 Low | Well-documented Gradle setup |

This becomes your roadmap for Phase 1.

### Step 5: Make a Go/No-Go Decision

Phase 0 ends with a decision:

- ✅ **Go:** All critical APIs verified, risks have mitigations, proceed to implementation
- ⚠️ **Pivot:** Major blockers found, need to change approach
- ❌ **No-Go:** Fundamental incompatibility, need different solution

For us, it was **Go**—but with an updated architecture.

---

## The Critical Discovery: No Singleton on Android

Here's what Phase 0 saved us from:

**iOS code we wanted to replicate:**
```objc
FlutterWebRTCPlugin *webrtcPlugin = [FlutterWebRTCPlugin sharedSingleton];
RTCMediaStreamTrack *track = [webrtcPlugin trackForId:trackId 
                                      peerConnectionId:peerConnectionId];
```

**What we discovered in Android source:**
```java
// FlutterWebRTCPlugin.java
public class FlutterWebRTCPlugin implements FlutterPlugin {
    private MethodCallHandlerImpl methodCallHandler;  // Instance variable, not static!
    
    // No getInstance() method
    // No sharedSingleton pattern
}
```

**The solution we found:**
```java
// MethodCallHandlerImpl.java implements StateProvider
public interface StateProvider {
    MediaStreamTrack getLocalTrack(String trackId);
}

public class MethodCallHandlerImpl implements MethodCallHandler, StateProvider {
    private final Map<String, MediaStreamTrack> localTracks = new HashMap<>();
    
    @Override
    public MediaStreamTrack getLocalTrack(String trackId) {
        return localTracks.get(trackId);
    }
}
```

**Our implementation:**
```kotlin
// Access via StateProvider interface using reflection
override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    try {
        val webrtcPlugin = binding.flutterEngine.plugins.get(
            Class.forName("com.cloudwebrtc.webrtc.FlutterWebRTCPlugin")
        )
        val handlerField = webrtcPlugin?.javaClass?.getDeclaredField("methodCallHandler")
        handlerField?.isAccessible = true
        stateProvider = handlerField?.get(webrtcPlugin) as? StateProvider
        
        Log.d(TAG, "✅ StateProvider accessed successfully")
    } catch (e: Exception) {
        Log.w(TAG, "⚠️ Could not access StateProvider: ${e.message}")
    }
}

// Later:
private fun getVideoTrack(trackId: String): VideoTrack? {
    val track = stateProvider?.getLocalTrack(trackId)
    return if (track is VideoTrack) track else null
}
```

If we'd started coding without Phase 0, we would have:
1. Implemented the iOS singleton pattern
2. Hit runtime errors
3. Spent hours debugging
4. Discovered the architectural difference
5. Refactored everything

Instead, we found the solution before writing a single line of production code.

---

## Real-World Phase 0 Examples

### Example 1: Dependency Location

**Assumption:** WebRTC AAR is in `flutter_webrtc/android/libs/`

**Phase 0 Finding:**
```bash
$ ls ~/.pub-cache/.../flutter_webrtc-0.11.7/android/libs/
ls: cannot access '...libs/': No such file or directory
```

**Reality:** It's a Maven dependency:
```gradle
dependencies {
    implementation 'io.github.webrtc-sdk:android:125.6422.03'
}
```

**Saved:** 1 hour of "why isn't my build working?"

### Example 2: YuvHelper Methods

**Assumption:** `YuvHelper.I420ToABGR()` exists (like iOS `RTCYUVHelper`)

**Phase 0 Finding:**
```bash
$ grep -r "I420ToABGR\|I420ToBGRA" android/
# No results
$ grep -r "YuvHelper" android/
android/src/.../FrameCapturer.java:import org.webrtc.YuvHelper;
android/src/.../FrameCapturer.java:YuvHelper.I420ToNV12(...)
```

**Reality:** Only `I420ToNV12` confirmed. Need runtime verification or fallback.

**Saved:** 2 hours of "why is my frame conversion crashing?"

### Example 3: Thread Safety

**Assumption:** Can call EventSink from any thread

**Phase 0 Finding:**
```java
// FrameCapturer.java line 91
new Handler(Looper.getMainLooper()).post(() -> {
    videoTrack.removeSink(this);
});
```

**Reality:** Must post to main thread.

**Saved:** 3 hours of intermittent crashes and race conditions.

---

## The Phase 0 Template

Here's a template you can use for your next project:

```markdown
# Phase 0 Research — [Project Name]

**Date:** [Date]
**Package/Library:** [Name and Version]
**Goal:** [What you're trying to build]

---

## 1. API Verification Checklist

- [ ] Critical API #1 — [description]
- [ ] Critical API #2 — [description]
- [ ] Critical API #3 — [description]

## 2. Findings

### Finding #1: [API Name]
**Status:** ✅ Confirmed / ⚠️ Partial / ❌ Not Available
**Location:** [File path and line number]
**Code Sample:**
```[language]
[actual code from source]
```
**Notes:** [Any surprises or gotchas]

### Finding #2: [API Name]
[Repeat structure]

## 3. Critical Architectural Decisions

[Document any major differences from assumptions]

## 4. Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| [Risk] | 🔴/🟡/🟢 | [Strategy] |

## 5. Implementation Strategy

[Updated approach based on findings]

## 6. Go/No-Go Decision

**Decision:** ✅ Go / ⚠️ Pivot / ❌ No-Go
**Reasoning:** [Why]
**Next Steps:** [What to do in Phase 1]

---

**Time Invested:** [X hours]
**Estimated Time Saved:** [Y hours/days]
```

[Download the template →](#)

---

## When to Use Phase 0

### Always Use Phase 0 When:

- ✅ Porting code between platforms (iOS ↔ Android)
- ✅ Integrating with undocumented or poorly documented libraries
- ✅ Building performance-critical features
- ✅ Working with native code (JNI, FFI, etc.)
- ✅ The cost of failure is high (production app, tight deadline)

### Phase 0 Is Overkill When:

- ❌ Using well-documented, stable APIs
- ❌ Building a quick prototype or POC
- ❌ The implementation is trivial (< 1 hour of work)
- ❌ You're already intimately familiar with the codebase

---

## The ROI of Phase 0

Let's do the math on our WebRTC plugin:

**Phase 0 Investment:**
- Research time: 4 hours
- Documentation time: 2 hours
- **Total: 6 hours (0.75 days)**

**Estimated Savings:**
- Avoided architectural rewrite: 8 hours
- Avoided dependency debugging: 2 hours
- Avoided thread safety debugging: 4 hours
- Avoided API discovery debugging: 3 hours
- **Total: 17 hours (2.1 days)**

**ROI: 283%** (17 hours saved / 6 hours invested)

But the real value isn't just time—it's confidence. We started Phase 1 knowing exactly what to build and how to build it.

---

## Common Phase 0 Mistakes

### Mistake #1: Reading Docs Instead of Source

Documentation lies. Not intentionally, but it's often outdated or incomplete.

**Bad:** "The docs say `getInstance()` exists, so I'll use it."
**Good:** "Let me grep the source to confirm `getInstance()` exists."

### Mistake #2: Not Documenting Findings

Your brain will forget. Future you will thank present you for writing it down.

**Bad:** "I'll remember that Android uses StateProvider."
**Good:** "I'll create PHASE_0_RESEARCH_FINDINGS.md with code samples."

### Mistake #3: Skipping Risk Assessment

Knowing a risk exists isn't enough—you need a mitigation plan.

**Bad:** "YuvHelper might not have I420ToABGR. I'll deal with it later."
**Good:** "If I420ToABGR is missing, I'll use io.github.crow-misia:libyuv-android:0.3.0 as fallback."

### Mistake #4: Doing Phase 0 Alone

Two pairs of eyes catch more issues than one.

**Bad:** Solo research, solo decisions.
**Good:** Pair on Phase 0, review findings with team, get buy-in on approach.

---

## Phase 0 Tools and Techniques

### Essential Tools

1. **grep / ripgrep** — Search source code
   ```bash
   grep -r "methodName" path/to/source/
   rg "methodName" path/to/source/  # faster
   ```

2. **find** — Locate files
   ```bash
   find . -name "*.java" -o -name "*.kt"
   ```

3. **cat / less** — Read source files
   ```bash
   cat path/to/file.java | head -100
   ```

4. **IDE navigation** — Jump to definition, find usages
   - Android Studio: Cmd+Click (Mac) / Ctrl+Click (Windows)
   - VS Code: F12 (Go to Definition)

### Advanced Techniques

1. **Reflection exploration** — Discover private APIs
   ```kotlin
   val clazz = Class.forName("com.example.Plugin")
   clazz.declaredFields.forEach { println(it.name) }
   clazz.declaredMethods.forEach { println(it.name) }
   ```

2. **Decompilation** — When source isn't available
   - Use jadx, JD-GUI, or Android Studio's decompiler

3. **Git history** — Understand why code exists
   ```bash
   git log -p path/to/file.java
   git blame path/to/file.java
   ```

4. **Issue trackers** — Learn from others' pain
   - Search GitHub issues for the library
   - Look for "Android" or "iOS" specific issues

---

## Phase 0 Success Stories

### Story 1: The Missing Singleton

**Project:** WebRTC pixel streaming plugin
**Phase 0 Finding:** Android has no singleton pattern
**Time Saved:** 2 days of refactoring
**Outcome:** Clean StateProvider reflection solution

### Story 2: The Maven Mystery

**Project:** Same plugin
**Phase 0 Finding:** WebRTC is Maven dependency, not local AAR
**Time Saved:** 1 day of build system debugging
**Outcome:** Correct build.gradle from day one

### Story 3: The Thread Safety Trap

**Project:** Same plugin
**Phase 0 Finding:** EventSink must be called on main thread
**Time Saved:** 3 days of intermittent crash debugging
**Outcome:** Handler pattern from the start

---

## Conclusion: Research Is Not Wasted Time

In software, we're trained to "move fast and break things." But sometimes, moving slowly and breaking nothing is the faster path.

Phase 0 is that path.

**The Phase 0 Mindset:**
- Assumptions are expensive
- Source code doesn't lie
- Documentation is a starting point, not the truth
- 6 hours of research beats 3 days of debugging
- Confidence comes from verification, not hope

**Your Phase 0 Checklist:**
1. ✅ Locate the source code
2. ✅ Verify every critical API
3. ✅ Document what you find
4. ✅ Identify risks and mitigations
5. ✅ Make a go/no-go decision

Next time you're about to start coding, ask yourself: "What am I assuming?" Then spend half a day verifying those assumptions.

Your future self will thank you.

---

## Resources

- 📄 [Phase 0 Template (Markdown)](#) — Download and customize
- 📄 [Our Complete Phase 0 Research](PHASE_0_RESEARCH_FINDINGS.md) — Real example
- 🎥 [Video: Phase 0 Walkthrough](#) — Watch us do Phase 0 live
- 💬 [Discussion: Your Phase 0 Stories](#) — Share your experiences

---

## What's Next?

This is Part 1 of our "Zero to Production: WebRTC Pixel Streaming" series.

**Coming next:**
- **Part 2:** iOS Implementation: FFI + vImage
- **Part 3:** Android Implementation: StateProvider + JNI
- **Part 4:** Testing & Benchmarking: 20fps → 30fps

Subscribe to get notified when Part 2 drops.

---

**About the Author:** Building high-performance Flutter apps with a focus on WebRTC, 360° video, and native platform integration. Currently working on Aura360, a 360° camera control system.

**Found this helpful?** Star the repo, share the post, or leave a comment with your Phase 0 stories!

---

*Published: March 31, 2026*  
*Reading time: 12 minutes*  
*Tags: #Flutter #SoftwareEngineering #BestPractices #WebRTC #TechnicalPlanning*
