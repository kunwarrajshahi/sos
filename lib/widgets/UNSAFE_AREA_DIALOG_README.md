# Unsafe Area Dialog - Implementation Guide

## Overview

A modern Flutter Material 3 dialog for reporting unsafe areas in the SafeRoute app. The dialog includes:
- Selectable reason chips (Poor lighting, Harassment, Isolated area)
- Time selection with preset chips (Night, Evening, Morning) and custom time range picker
- Modern Material 3 design with soft shadows and animations
- Mobile-friendly responsive layout
- Red accent color for unsafe-related selections

## Features

✨ **Modern Design**
- Material 3 design principles with rounded corners (28dp)
- Soft shadows and smooth animations
- Responsive layout for mobile and tablet

🎨 **Visual Feedback**
- Chip selection highlighting with red borders
- Scale animations on chip selection
- Custom time picker with animated appearance

⏰ **Time Selection**
- Preset time options: Night (🌙), Evening (🌅), Morning (🌅)
- Custom time range picker with start/end times
- Display of selected time range below picker

📍 **Data Handling**
- Captures location (latitude, longitude)
- Stores selected reason and time information
- Exports data as JSON-compatible format

## File Structure

```
lib/
├── widgets/
│   └── unsafe_area_dialog.dart      # Main dialog widget
├── screens/
│   └── unsafe_area_demo_screen.dart # Demo screen (optional)
```

## Usage

### Basic Implementation

```dart
import 'package:safe_route/widgets/unsafe_area_dialog.dart';

// Show the dialog
showDialog(
  context: context,
  builder: (context) => UnsafeAreaDialog(
    latitude: 28.6,
    longitude: 77.2,
    onConfirm: (data) {
      print('Unsafe area reported: ${data.toJson()}');
      // Save to Firebase or your backend
    },
    onCancel: () {
      print('Dialog cancelled');
    },
  ),
);
```

### Integration with a Button

```dart
FloatingActionButton(
  onPressed: () {
    showDialog(
      context: context,
      builder: (context) => UnsafeAreaDialog(
        latitude: userLocation.latitude,
        longitude: userLocation.longitude,
        onConfirm: (data) {
          // Handle the reported unsafe area
          _submitUnsafeAreaReport(data);
        },
      ),
    );
  },
  child: const Icon(Icons.warning),
)
```

## API Reference

### `UnsafeAreaDialog`

**Constructor Parameters:**
- `onConfirm` (required): Callback when user confirms the report
- `onCancel` (optional): Callback when user cancels
- `latitude` (required): Location latitude
- `longitude` (required): Location longitude

### `UnsafeAreaData`

**Properties:**
- `latitude`: double - User's latitude
- `longitude`: double - User's longitude
- `reason`: String? - Selected reason (poor_lighting, harassment, isolated_area)
- `timeType`: String? - Selected time type (night, evening, morning, custom)
- `timeStart`: String? - Custom start time (HH:mm format)
- `timeEnd`: String? - Custom end time (HH:mm format)

**Methods:**
- `toJson()`: Converts data to JSON-compatible Map

### Example JSON Output

```json
{
  "location": {
    "lat": 28.6,
    "lng": 77.2
  },
  "reason": "poor_lighting",
  "time_type": "custom",
  "time_start": "20:00",
  "time_end": "02:00"
}
```

## Customization

### Change Colors

To modify the accent color (currently red), update the hardcoded `Colors.red` references:

```dart
// In unsafe_area_dialog.dart, replace Colors.red with your color
// Example: Using app's theme color
final accentColor = Theme.of(context).colorScheme.primary;
```

### Add More Reason Options

```dart
reasonOptions = [
  ReasonOption(id: 'custom', label: 'Custom Reason', icon: Icons.flag),
  // ... existing options
];
```

### Add More Time Options

```dart
timeOptions = [
  TimeOption(id: 'late_night', label: 'Late Night', emoji: '🌃'),
  // ... existing options
];
```

## Material 3 Design Features Used

1. **Color Scheme**: Uses `colorScheme` from theme
2. **Surface Containers**: Proper hierarchy with `surfaceContainerHigh`
3. **Typography**: TextTheme styles (headlineSmall, titleMedium, labelLarge, etc.)
4. **Shapes**: 28dp dialog corners, 20dp chips, 12dp buttons
5. **Elevation**: Soft shadows instead of hard elevation values
6. **Spacing**: Consistent spacing scale (8px, 12px, 16px, 24px, 28px, 32px)

## Accessibility Considerations

- ✅ Proper contrast ratios for text
- ✅ Touch targets >= 48x48 dp
- ✅ Semantic labels for IconButtons
- ✅ ScrollView for content overflow on small screens

## Performance Notes

- Uses `TickerProviderStateMixin` for efficient animations
- `SingleChildScrollView` prevents layout overflow on small screens
- Animation controller properly disposed in cleanup
- Minimal rebuilds with strategic `setState` calls

## Integration with Firebase

```dart
Future<void> _submitUnsafeAreaReport(UnsafeAreaData data) async {
  try {
    await FirebaseFirestore.instance
        .collection('unsafe_areas')
        .add({
          ...data.toJson(),
          'timestamp': FieldValue.serverTimestamp(),
          'userId': currentUser.uid,
        });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Area reported successfully')),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: $e')),
    );
  }
}
```

## Testing the Dialog

Visit `unsafe_area_demo_screen.dart` for a complete demo implementation that you can navigate to and test the dialog functionality.

```dart
// In main.dart or your navigation
'/unsafe-area-demo': (context) => const UnsafeAreaDemoScreen(),
```

## Browser Support

This is a Flutter Mobile/Desktop widget - not supported on web platform. For web, consider using BottomSheet or an alternative layout.

## Known Limitations

1. Time picker uses system TimePicker (iOS: Cupertino, Android: Material)
2. Custom time validation is not enforced (end time can be before start time)
3. Requires Material context for ThemeData access

## Future Enhancements

- [ ] Custom reason text input field
- [ ] Time validation (end time > start time)
- [ ] Photo/evidence upload support
- [ ] Anonymous reporting toggle
- [ ] Report severity level selector
- [ ] Multi-select reasons
