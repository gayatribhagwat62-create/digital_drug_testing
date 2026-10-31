# Problem Statement Title : Digital Companion for Field Drug Testing
# Smart India Hackathon 2026 Prototype


### A Smart Digital Solution for Colorimetric Field Drug Testing

## 📌 About the Project

Digital Drug Testing Companion is a Flutter-based mobile application prototype designed to support field officers in documenting and managing colorimetric drug testing procedures.

The application integrates image capture, color-reference comparison, prototype image analysis, GPS-based location tagging, timestamp recording, and secure digital evidence management into a single platform.

It aims to improve the consistency, traceability, transparency, and digital documentation of field drug testing activities while supporting existing colorimetric drug testing kits.

## 🎯 Objectives

- Digitize field drug testing documentation.
- Support standardized image capture and color-reference comparison.
- Assist in preliminary colorimetric test interpretation.
- Maintain traceable and tamper-evident digital records.
- Reduce manual recordkeeping.
- Generate structured digital reports for field documentation.

## ✨ Key Features

- **Officer Login:** Operator identification and login interface.
- **Dashboard:** Overview of testing activities and statistics.
- **Automated Case ID:** Unique case and sample ID generation.
- **Image Capture:** Capture test-kit images using the mobile camera.
- **Demo Image Selection:** Preloaded test images for prototype demonstrations.
- **Color Reference Chart:** Digital reference colors for selected substances.
- **Prototype Image Analysis:** Preliminary image-based result classification with confidence information.
- **GPS Integration:** Capture geographical coordinates and location accuracy.
- **Timestamp Tracking:** Automatic date and time recording.
- **SHA-256 Image Hashing:** Image integrity verification support.
- **QR Code Generation:** QR-based digital record verification.
- **PDF Reports:** Generate and print structured test reports.
- **Offline Record Storage:** Maintain test records locally using Hive.
- **Test History:** View saved records and their details.

## 🔄 Application Workflow

1. Officer logs into the application.
2. Creates a new field test.
3. Enters test kit information.
4. Captures or selects a test image.
5. Performs prototype image analysis.
6. Views the preliminary result and confidence information.
7. Records GPS coordinates and timestamp.
8. Generates SHA-256 hash and QR verification data.
9. Saves the digital test record.
10. Generates a PDF report.

## 🛠️ Technology Stack

| Technology | Purpose |
|---|---|
| Flutter | Mobile application development |
| Dart | Programming language |
| Camera Plugin | Image capture |
| Image Processing | Image analysis |
| Geolocator | GPS integration |
| Hive CE | Local data storage |
| Crypto | SHA-256 hashing |
| QR Flutter | QR code generation |
| PDF | Report generation |
| Printing | PDF printing |

## 🚀 Getting Started

### Prerequisites

- Flutter SDK
- Dart SDK
- Android SDK
- Android mobile device or emulator
- VS Code or Android Studio

### Installation

Clone the repository:

```bash
git clone https://github.com/gayatribhagwat62-create/digital_drug_testing.git
```

Navigate to the project directory:

```bash
cd digital_drug_testing
```

Install dependencies:

```bash
flutter pub get
```

Run the application:

```bash
flutter run
```

## 📱 Project Platform

- Android Mobile Application
- Developed using Flutter
- Designed for field-testing workflow demonstrations.

## ⚠️ Important Disclaimer

This application is an academic and innovation prototype. Its outputs are preliminary and must not be treated as confirmed forensic or laboratory results. Colorimetric field tests are presumptive screening tools, and laboratory confirmation by authorized professionals is required.

The prototype's QR and SHA-256 features support record-integrity demonstrations; they do not independently establish forensic authenticity.

## 🔮 Future Enhancements

- Advanced machine learning-based color analysis.
- Reference-card calibration under varying lighting conditions.
- Secure cloud-based data synchronization.
- Role-based access control.
- Advanced evidence audit trails.
- Integration with authorized laboratory systems.

## 👩‍💻 Project Information

**Project Name:** Digital Drug Testing Companion

**Domain:** MedTech

**Development Framework:** Flutter

**Project Type:** SIH 2026 Prototype

**Repository:** (https://github.com/gayatribhagwat62-create/digital_drug_testing)

---

*Developed as an innovative prototype to support digital transformation in field drug testing.*
