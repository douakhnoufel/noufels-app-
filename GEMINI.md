# 🥔 PlantGuard — Potato Disease Detector

## Project Overview
PlantGuard is a high-performance Flutter mobile application designed for real-time detection of potato leaf diseases. It leverages a **YOLOv8n** model converted to **TFLite** to classify leaves into three categories: Early Blight, Late Blight, and Healthy.

The project also contains a secondary React Native project (`PotatoDetector/`), which currently serves as a boilerplate/placeholder.

### Main Technologies
- **Framework:** Flutter (Material 3)
- **Inference:** TFLite via `tflite_flutter` (local package in `packages/tflite_flutter`)
- **Image Processing:** `image` package and custom YUV/BGRA conversion logic.
- **UI/UX:** `google_fonts` (Inter), `flutter_animate`, `percent_indicator`.

---

## 📁 Architecture

### Core Services (`lib/services/`)
- **`ClassifierService`**: The primary API for the application. It maps raw inference probabilities to human-readable results, including descriptions and agricultural recommendations.
- **`ImagePreprocessor`**: Optimized image handling. Uses Flutter isolates (`compute`) to perform resizing and normalization without blocking the UI thread. Supports:
  - Standard Image files (JPEG/PNG)
  - Camera frames in `BGRA8888` (iOS) and `YUV420` (Android) formats.
- **`InferenceEngine`**: Manages the TFLite `Interpreter` lifecycle. It uses a sequential queue (`_queue`) to ensure that overlapping camera frames don't cause race conditions during inference.

### Key Screens (`lib/screens/`)
- **`SplashScreen`**: Handles initial model loading and provides a branded entry point.
- **`HomeScreen`**: Entry point for three detection modes: Camera Capture, Gallery Import, and Live Stream.
- **`LiveCameraScreen`**: Implements real-time detection with a scanning overlay.
- **`ResultScreen`**: Displays detailed diagnosis, confidence charts, and treatment recommendations.

---

## 🚀 Building and Running

### Prerequisites
- Flutter SDK (>= 3.0.0)
- Android Studio / Xcode
- A physical device (required for camera/live mode)

### Key Commands
- **Install Dependencies:** `flutter pub get`
- **Run App:** `flutter run`
- **Build Android APK:** `flutter build apk --release`
- **Build iOS IPA:** `flutter build ipa --release`

### Android Configuration Note
The `android/app/build.gradle.kts` file must include the following to prevent TFLite model compression:
```kotlin
androidResources {
    noCompress += "tflite"
}
```

---

## 🛠️ Development Conventions

- **State Management:** The app primarily uses local state and constructor-based dependency injection for services.
- **Orientation:** Locked to **Portrait** mode via `SystemChrome`.
- **Model Assets:** The app currently loads `assets/models/best_float32.tflite` from `ClassifierService`.
- **Testing:**
  - Standard widget tests are in `test/`.
  - Manual verification is recommended using images from the PlantVillage dataset.

---

## 📦 Secondary Projects
- **`PotatoDetector/`**: A React Native (v0.85) project. Currently a clean boilerplate with no custom logic implemented. It uses TypeScript and Jest for testing.
