1. Project Overview (Elevator Pitch)
Muzician is a high-performance Flutter music theory application. It focuses on interactive visual tools (Fretboard, Piano, Piano Roll) using custom rendering to provide a seamless educational experience for musicians.

2. Tech Stack & Environment
Framework: Flutter 3.x+ (utilizing the Impeller rendering engine).

Language: Dart with strict "sound null safety" and Effective Dart style.

State Management: Riverpod 2.x using NotifierProvider and StateProvider.

Rendering: Heavy use of CustomPainter wrapped in RepaintBoundary.

Data Models: Immutable types using copyWith patterns.

Dependencies: music_notes (logic), audioplayers (sound), shared_preferences (storage).

3. Documentation Strategy (Diátaxis)
All documentation must be categorized into one of the four Diátaxis quadrants:

Tutorials: Learning-oriented; step-by-step lessons for newcomers.

How-to Guides: Problem-oriented; specific "recipes" for tasks.

Reference: Information-oriented; technical descriptions of API/State.

Explanation: Understanding-oriented; deep dives into "why" decisions were made.

Synchronization Rules
README First: Always consult README.md before updating docs/. The README is the high-level map.

Bidirectional Sync: When a feature is added to docs/, the "Features" table in the README.md must be updated. When the tech stack in the README changes, all reference docs must be audited.

4. Coding Standards
Consistency: Follow the "Effective Dart" guidelines (UpperCamelCase for types, lowerCamelCase for constants).

Architecture: Maintain a strict separation between the Data Layer (Repositories/Models) and the UI Layer (ViewModels/Widgets).

UI Logic: Do not put business logic in Widgets. Widgets should only handle layout and simple visibility flags.

Performance: Use RepaintBoundary for any widget using a CustomPainter to prevent unnecessary global repaints.

5. Project Structure
Refer to this tree to locate logic:

lib/models/: Immutable data structures.

lib/store/: Riverpod providers (State Layer).

lib/features/: Feature-specific UI and painters.

lib/schema/rules/: Music theory math and validation logic.

docs/: Feature-specific documentation files.