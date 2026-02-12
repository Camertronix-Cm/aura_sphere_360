# Publishing to pub.dev

## ✅ Pre-Publication Checklist

All items completed:

- [x] Package validated with `flutter pub publish --dry-run`
- [x] No warnings or errors
- [x] Version updated to 2.1.0
- [x] CHANGELOG.md updated
- [x] README.md updated with video examples
- [x] LICENSE file present (Apache 2.0)
- [x] All code committed to git
- [x] Tested on iOS device
- [x] Documentation complete

## 📋 Publication Steps

### Step 1: Final Validation

```bash
flutter pub publish --dry-run
```

Expected output: "Package has 0 warnings"

### Step 2: Push to GitHub

```bash
git push origin feature/video-support
```

### Step 3: Create a Release Tag

```bash
git tag v2.1.0
git push origin v2.1.0
```

### Step 4: Publish to pub.dev

```bash
flutter pub publish
```

You'll be prompted to:
1. Confirm the package details
2. Authenticate with your Google account
3. Confirm publication

### Step 5: Verify Publication

Visit: https://pub.dev/packages/panorama_viewer

The package should appear within a few minutes.

## 🔐 Authentication

You need to be authenticated with pub.dev:

1. Run `flutter pub publish`
2. Follow the authentication link
3. Sign in with your Google account
4. Grant permissions
5. Return to terminal and confirm

## 📝 What Gets Published

The following will be included in the package:

### Core Files
- `lib/` - All Dart source code
- `android/` - Android platform code
- `ios/` - iOS platform code
- `pubspec.yaml` - Package configuration
- `README.md` - Package documentation
- `CHANGELOG.md` - Version history
- `LICENSE` - Apache 2.0 license

### Documentation
- `DEPLOYMENT_GUIDE.md`
- `QUICK_START.md`
- `RELEASE_NOTES.md`
- `TESTING_GUIDE.md`
- All phase documentation files

### Example App
- `example/` - Complete working example

## 🚫 What's Excluded

The following are automatically excluded:
- `.git/` - Git repository
- `.dart_tool/` - Build artifacts
- `build/` - Compiled files
- `.idea/`, `.vscode/` - IDE settings

## 📊 Package Information

```yaml
name: panorama_viewer
version: 2.1.0
description: A 360-degree panorama viewer widget with support for both images and videos
homepage: https://github.com/Camertronix-Cm/panorama_viewer
repository: https://github.com/Camertronix-Cm/panorama_viewer
issue_tracker: https://github.com/Camertronix-Cm/panorama_viewer/issues
```

## 🎯 After Publication

### 1. Verify the Package

- Visit https://pub.dev/packages/panorama_viewer
- Check that version 2.1.0 is listed
- Verify the README displays correctly
- Check the example tab
- Review the changelog

### 2. Test Installation

Create a new Flutter project and test:

```bash
flutter create test_panorama
cd test_panorama
```

Add to `pubspec.yaml`:
```yaml
dependencies:
  panorama_viewer: ^2.1.0
```

```bash
flutter pub get
```

### 3. Update Your Apps

Update your Aura360 app to use the published version:

```yaml
dependencies:
  panorama_viewer: ^2.1.0  # Instead of git dependency
```

### 4. Announce the Release

Consider announcing on:
- GitHub Releases page
- Flutter community forums
- Social media
- Your app's changelog

## 🔄 Future Updates

For future versions:

1. Update version in `pubspec.yaml`
2. Update `CHANGELOG.md`
3. Commit changes
4. Create git tag
5. Run `flutter pub publish`

## 📞 Support

If you encounter issues:

1. **Authentication Problems**
   - Clear pub cache: `flutter pub cache repair`
   - Try again: `flutter pub publish`

2. **Validation Errors**
   - Run: `flutter pub publish --dry-run`
   - Fix any reported issues
   - Try again

3. **Package Already Exists**
   - You can only publish if you own the package name
   - Contact pub.dev support if needed

## ⚠️ Important Notes

1. **Cannot Unpublish**: Once published, versions cannot be removed (only marked as discontinued)
2. **Version Numbers**: Must follow semantic versioning (major.minor.patch)
3. **Breaking Changes**: Increment major version for breaking changes
4. **Package Name**: `panorama_viewer` is already registered to you

## 🎉 Ready to Publish!

Your package is ready for publication. Run:

```bash
flutter pub publish
```

And follow the prompts!

---

## Quick Command Reference

```bash
# Validate
flutter pub publish --dry-run

# Create tag
git tag v2.1.0
git push origin v2.1.0

# Publish
flutter pub publish

# Verify
open https://pub.dev/packages/panorama_viewer
```

**Good luck with your publication! 🚀**
