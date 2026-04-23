# Unsafe Area Dialog - Component Guide

## Visual Layout

```
┌─────────────────────────────────┐
│  Mark Unsafe Area               │  ← Title (headline-small, bold)
│  Do you want to mark this       │  ← Subtitle (body-medium)
│  area as unsafe?                │
├─────────────────────────────────┤
│ Select Reason (Optional)        │  ← Section Title (title-medium)
│                                 │
│ [💡 Poor lighting] [🔒 Harass] │  ← Chips with icons
│ [📍 Isolated area]              │
├─────────────────────────────────┤
│ Select Time (Optional)          │  ← Section Title (title-medium)
│                                 │
│ [🌙 Night] [🌅 Evening]         │  ← Preset time chips
│ [🌅 Morning] [⏰ Custom Time]    │
│                                 │
│ ┌─────────────────────────────┐ │  ← Custom time picker (if selected)
│ │ Select Time Range           │ │
│ │ [Start] [--:--] [End] [--:--]│ │
│ │ [20:00 - 02:00]             │ │
│ └─────────────────────────────┘ │
├─────────────────────────────────┤
│ [Cancel]        [Confirm]       │  ← Action buttons
└─────────────────────────────────┘
```

## Component Details

### 1. Header Section
- **Title**: "Mark Unsafe Area" (headline-small, bold)
- **Subtitle**: "Do you want to mark this area as unsafe?" (body-medium, secondary color)
- **Spacing**: 8px between title and subtitle
- **Colors**: Uses theme's `onSurface` and `onSurfaceVariant`

### 2. Reason Section
- **Title**: "Select Reason (Optional)" (title-medium, semi-bold)
- **Type**: Multi-chip selection (one at a time)
- **Chips Available**:
  - 💡 Poor lighting
  - 🔒 Harassment
  - 📍 Isolated area
- **Styling**:
  - Unselected: Gray background (`surfaceContainerHigh`)
  - Selected: Light red background + red border
  - Icons: 18px size
  - Padding: 16px horizontal, 10px vertical
  - Corner radius: 20px

### 3. Time Section
- **Title**: "Select Time (Optional)" (title-medium, semi-bold)
- **Type**: Multi-chip selection
- **Preset Chips**:
  - 🌙 Night
  - 🌅 Evening
  - 🌅 Morning
- **Custom Chip**:
  - ⏰ Custom Time
  - Opens time range picker on selection

### 4. Custom Time Picker (Conditional)
- **Appearance**: Animated slide-in with red-tinted background
- **Container**: Red-tinted (Colors.red.shade50)
- **Components**:
  - Start Time button: Shows "--:--" when empty
  - End Time button: Shows "--:--" when empty
  - Time range display: Shows "HH:mm - HH:mm" format
- **Styling**:
  - Container padding: 16px
  - Button padding: 12px
  - Border radius: 12px
  - Display background: White with opacity

### 5. Button Section
- **Layout**: Row with two buttons taking equal space
- **Cancel Button**:
  - Type: Outlined Button
  - Border: Uses theme's `outline` color
  - Padding: 14px vertical
  - Corner radius: 12px
- **Confirm Button**:
  - Type: Filled Button
  - Background: Red (Colors.red)
  - Shadow: Red with 0.4 opacity
  - Elevation: 4
  - Padding: 14px vertical
  - Corner radius: 12px
- **Spacing**: 12px between buttons

## Responsive Behavior

### Mobile (< 600px width)
- Dialog padding: 16px horizontal, 24px vertical
- Content scrollable for overflow
- Touch targets: >= 48x48 dp
- Buttons: Stack vertically if needed (current: side-by-side)

### Tablet (≥ 600px width)
- Dialog padding: 24px horizontal, 24px vertical
- Maximum width: Device width - 48px

## Color Scheme

### Light Theme
- **Surface**: Background color
- **OnSurface**: Text (titles, labels)
- **OnSurfaceVariant**: Secondary text (subtitles, descriptions)
- **SurfaceContainerHigh**: Unselected chip background
- **Outline**: Button borders
- **Red**: Accent color for unsafe selections

### Dark Theme
- All colors automatically adapt via Material 3 ColorScheme
- Red accent maintained for safety emphasis

## Typography

| Element | Style | Font Weight |
|---------|-------|-------------|
| Title | headlineSmall | Bold (700) |
| Subtitle | bodyMedium | Regular (400) |
| Section Title | titleMedium | Semi-bold (600) |
| Chip Label | labelLarge | Medium-Bold (500-600) |
| Button Text | labelLarge | Default (500) |
| Time Display | labelMedium | Semi-bold (600) |
| Helper Text | labelSmall | Medium (500) |

## Spacing Scale

All spacing follows Material 3 8px base unit:
- **4px**: Not used (prefer 8px minimum)
- **8px**: Internal element gaps
- **12px**: Between sections, button spacing
- **16px**: Container padding
- **24px**: Dialog padding, large section spacing
- **28px**: Large gaps between major sections
- **32px**: Pre-button spacing

## Animations

### Chip Selection
- **Type**: Scale animation
- **Duration**: 300ms
- **Curve**: easeOut
- **Range**: 0.9 → 1.0 (90% → 100%)
- **Trigger**: On chip tap

### Custom Time Picker
- **Type**: AnimatedContainer height/opacity change
- **Duration**: 300ms
- **Effect**: Slide down with fade-in

### Shadow on Hover
- **Selected chip**: Soft shadow with red tint
- **Button hover**: Standard material ripple

## Interactive States

### Chips
```
Unselected (default):
├─ Background: surfaceContainerHigh
├─ Border: Transparent
├─ Text color: onSurfaceVariant
└─ Shadow: None

Selected:
├─ Background: Colors.red.shade50
├─ Border: Red 2px
├─ Text color: Colors.red
├─ Font weight: 600
└─ Shadow: Red with 0.2 opacity
```

### Buttons
```
Cancel Button:
├─ Default: White/Transparent with outline
├─ Hover: Ripple effect
└─ Pressed: Ink ripple

Confirm Button:
├─ Default: Solid red with elevation
├─ Hover: Ripple effect
├─ Pressed: Increased elevation
└─ Disabled: Opacity reduced
```

## Accessibility Features

✅ **Touch Targets**: All interactive elements ≥ 48x48 dp
✅ **Contrast**: WCAG AA compliant text contrast
✅ **Semantic Structure**: Proper heading hierarchy
✅ **Keyboard Navigation**: Full keyboard support
✅ **Screen Readers**: Material widgets provide labels
✅ **Focus Indicators**: Visible focus on navigation
✅ **Visual Feedback**: Multiple sensory cues for selection

## Edge Cases

### Empty Selection
- User can submit without selecting anything
- Both reason and time are optional
- Consider adding validation if required

### Time Validation
- No validation that end time > start time
- Custom times can be equal or reversed
- Consider adding validation warning

### Content Overflow
- Dialog uses SingleChildScrollView
- Scrolls vertically on small screens
- Maintains 24px vertical padding

## Dark Mode Support

The dialog automatically adapts to dark theme:
- Surface colors invert appropriately
- Red accent remains consistent
- Text contrasts adjust automatically
- Shadows adjust opacity for visibility

## Browser/Platform Specific

| Platform | TimePicker | Behavior |
|----------|-----------|----------|
| Android | Material TimePicker | Native-looking |
| iOS | Cupertino TimePicker | Native-looking |
| Web | HTML5 time input | N/A (mobile widget) |
| Windows | Material TimePicker | Material Design |
| macOS | Cupertino TimePicker | Cupertino Design |

## Performance Notes

- Dialog rebuilds only when state changes
- Animations use AnimationController (not implicit)
- SingleChildScrollView only when needed
- No memory leaks in animation disposal

## Localization Considerations

Current text is in English. To add localization:

```dart
// In your l10n files
'markUnsafeArea': 'Mark Unsafe Area',
'selectReason': 'Select Reason (Optional)',
'selectTime': 'Select Time (Optional)',
'poorLighting': 'Poor lighting',
// ... etc
```

Then update the widget to use localized strings via `AppLocalizations.of(context)`.
