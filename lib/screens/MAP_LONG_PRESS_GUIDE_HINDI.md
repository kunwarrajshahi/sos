# 🗺️ Unsafe Area Map Screen - Use Guide (Hindi/Hinglish)

## 📱 Kya Kar Sakta Hai Ye Screen?

### Main Features:
1. **Map Pe Long Press Karo** → Dialog khul jayega
2. **Reason Select Karo** → Harassment, Poor Lighting, Isolated Area
3. **Time Enter Karo** → Kab area unsafe tha (Night, Evening, Morning, ya Custom Time)
4. **Confirm Karo** → Map pe red marker aa jayega
5. **Marker Tap Karo** → Details dekh sakte ho

---

## 🚀 Quick Setup

### Step 1: Import Screen Ko Main.dart Mein Add Karo

```dart
import 'package:safe_route/screens/unsafe_area_map_screen.dart';

// Navigation ke liye
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const UnsafeAreaMapScreen(),
  ),
);
```

### Step 2: Saath Mein Route Add Kar Do

```dart
routes: {
  '/unsafe-map': (context) => const UnsafeAreaMapScreen(),
}

// Phir anywhere se navigate kar sakte ho:
Navigator.pushNamed(context, '/unsafe-map');
```

---

## 📍 Kaise Use Kare?

### Step-by-Step Process:

```
1. Screen kholo
   ↓
2. Map dikhai dega (Delhi initial location)
   ↓
3. Map pe long press karo (2-3 seconds)
   ↓
4. Dialog khul jayega
   ↓
5. Options select karo:
   - Reason (Poor lighting, Harassment, Isolated area)
   - Time (Night, Evening, Morning, ya Custom)
   ↓
6. Confirm button click karo
   ↓
7. Red marker map pe aa jayega
   ↓
8. Marker tap karo details dekh ne ke liye
```

---

## 🎯 Dialog Options Explained

### Reason Options (Reasons):

| Icon | Label | Matlab |
|------|-------|--------|
| 💡 | Poor lighting | Raat ko andhere area mein danger |
| 🔒 | Harassment | Wahan pe log harassment karte hain |
| 📍 | Isolated area | Bahut akela/alag area hai |

### Time Options (Samay):

| Emoji | Label | Matlab |
|-------|-------|--------|
| 🌙 | Night | Raat ko (20:00 - 06:00) |
| 🌅 | Evening | Shaam ko (17:00 - 19:00) |
| 🌅 | Morning | Subah ko (06:00 - 12:00) |
| ⏰ | Custom Time | Apna samay select karo |

---

## ⏰ Custom Time Kaise Set Kare?

### Agar Specific Time Chaiye:

```
1. Dialog mein "⏰ Custom Time" chip select karo
   ↓
2. Naya section aa jayega
   ↓
3. "Start Time" click karo
   → Time picker khulega
   → Time select karo (e.g., 20:00)
   ↓
4. "End Time" click karo
   → Time picker khulega
   → Time select karo (e.g., 23:00)
   ↓
5. Dono times dikh jayenge: "20:00 - 23:00"
   ↓
6. Confirm karo
```

---

## 🔴 Map Pe Red Markers

### Markers Ka Matlab:

```
Red Circle = Unsafe Area Marker
├─ Tap karo → Details dialog
├─ Reason, Time, Location dikhai dega
└─ Delete button se remove kar sakte ho
```

### Marker Icon (Reason Se):

```
💡 Poor Lighting → Bulb icon
🔒 Harassment → Lock/Security icon
📍 Isolated Area → Location icon
⚠️ No Reason → Warning icon
```

---

## 💾 Data Kahan Save Hota Hai?

### Local Storage (Abhi):
- Markers app mein rakhe hote hain
- App close karne se data delete ho jayega

### Firebase Mein Save Karne ke Liye:

```dart
// unsafe_area_map_screen.dart mein _addMarkerToMap method mein add karo:

void _addMarkerToMap(UnsafeAreaData data) {
  // ... existing code ...
  
  // Firebase mein save karo
  FirebaseFirestore.instance
      .collection('unsafe_areas')
      .add({
        ...data.toJson(),
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
}
```

---

## 🗺️ Map Details

### Initial Location:
```dart
// Delhi center (28.6139, 77.2090)
// Aap apna location set kar sakte ho:
center: LatLng(yourLat, yourLng),
```

### Map Provider:
- OpenStreetMap (Free)
- Koi API key nahi chahiye
- World mein kaam karta hai

---

## 🎨 UI Colors

```
Dialog:
├─ Title & Subtitle: White/Gray
├─ Unselected Chips: Light Gray
├─ Selected Chips: Light Red (Red Border)
└─ Confirm Button: Bright Red

Map:
├─ Markers: Red Circle with Icon
├─ Instructions: Blue Box
└─ Area Counter: Red Chip
```

---

## ❌ Debugging Tips

### Agar Dialog Nahi Khul Raha:

```dart
// Long press detect nahi ho raha?
// Check karo:
1. flutter_map aur latlong2 pubspec.yaml mein hain?
2. MapOptions mein onLongPress set hai?
3. GestureDetector layer add kiya hai?
```

### Agar Marker Nahi Aa Raha:

```dart
// Check karo:
1. MarkerLayer add kiya hai?
2. unsafeMarkers list mein add ho raha hai?
3. setState() call ho raha hai?
```

### Agar Time Nahi Set Ho Raha:

```dart
// Custom Time picker:
1. "Custom Time" chip select karo
2. Start/End buttons click karo
3. Time display dikhai do ("HH:mm - HH:mm")
4. Phir Confirm karo
```

---

## 📊 Data Output Example

### Jab Confirm Karte Ho:

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

### Console Output:

```
📍 Unsafe Area Reported:
Latitude: 28.6
Longitude: 77.2
Reason: poor_lighting
Time: 20:00 - 02:00
Full Data: {...}
```

---

## 🔒 Safety Features

✅ **Timestamp** - Kab report kiya
✅ **Reason** - Kyun unsafe hai
✅ **Time Range** - Kab se kab tak unsafe hai
✅ **Exact Location** - GPS coordinates
✅ **Visual Feedback** - Success/Error messages

---

## 🚀 Next Steps

### Firebase Integration Karne Ke Baad:

1. Reports database mein save ho jayenge
2. Other users ko dikhe ge unsafe areas
3. Analytics collect kar sakte ho
4. Heat map banaa sakte ho

### Example Firebase Integration:

```dart
Future<void> _saveToFirebase(UnsafeAreaData data) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login karni padegi')),
      );
      return;
    }

    await FirebaseFirestore.instance
        .collection('unsafe_areas')
        .add({
          ...data.toJson(),
          'userId': user.uid,
          'userName': user.displayName ?? 'Anonymous',
          'timestamp': FieldValue.serverTimestamp(),
          'verified': false,
          'reports': 1,
        });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ Area safely reported!'),
        backgroundColor: Colors.green,
      ),
    );
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('❌ Error: $e'),
        backgroundColor: Colors.red,
      ),
    );
  }
}
```

---

## 📱 Mobile-Friendly Features

✅ Full responsive design
✅ Touch-friendly button sizes (48x48 dp minimum)
✅ Proper spacing for thumbs
✅ Scrollable dialog on small screens
✅ Landscape support

---

## 🎓 Code Structure

```
UnsafeAreaMapScreen (StatefulWidget)
├── initState() - Map controller setup
├── _onMapLongPress() - Dialog trigger
├── _showUnsafeAreaDialog() - Dialog show
├── _addMarkerToMap() - Marker add
├── _showMarkerDetails() - Details dialog
├── _buildUnsafeMarker() - Marker UI
└── build() - Main UI
```

---

## ✨ Tips & Tricks

### Tip 1: Zoom In/Out
```dart
mapController.move(
  const LatLng(28.6139, 77.2090),
  15, // Zoom level
);
```

### Tip 2: Custom Initial Location
```dart
// Screen create karte waqt:
class UnsafeAreaMapScreen extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  
  const UnsafeAreaMapScreen({
    this.initialLat = 28.6139,
    this.initialLng = 77.2090,
  });
}
```

### Tip 3: Filter Markers by Reason
```dart
// Sirf Poor Lighting markers dikhana:
final lightingMarkers = unsafeMarkers.where(
  (m) => m.data.reason == 'poor_lighting'
).toList();
```

---

## 🆘 Common Issues & Solutions

| Issue | Solution |
|-------|----------|
| Dialog button click nahi ho raha | Material context check karo |
| Markers map pe nahi dikhe | MarkerLayer properly add karo |
| Time nahi select ho pa raha | Custom Time chip select karo |
| Long press kaam nahi kar raha | Map options mein onLongPress check karo |

---

## 📞 Questions?

- **Dialog nahi khul raha?** → Check onLongPress in MapOptions
- **Marker nahi aa raha?** → setState() properly call ho?
- **Data nahi save ho raha?** → Firebase setup complete?
- **Time options nahi dikhe?** → ScrollView check karo

---

**Last Updated**: April 23, 2026
**Language**: Hindi/Hinglish
**Status**: ✅ Ready to Use
