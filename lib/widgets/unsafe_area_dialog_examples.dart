import 'package:flutter/material.dart';
import 'package:safe_route/widgets/unsafe_area_dialog.dart';

/// Quick Reference Examples for UnsafeAreaDialog
///
/// This file contains common implementation patterns and use cases.

// ============================================================================
// Example 1: Simple Dialog with Minimal Setup
// ============================================================================

class Example1_SimpleDialog extends StatelessWidget {
  const Example1_SimpleDialog({super.key});

  void _showDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => UnsafeAreaDialog(
        latitude: 28.6,
        longitude: 77.2,
        onConfirm: (data) {
          print('Report submitted: ${data.toJson()}');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => _showDialog(context),
          child: const Text('Report Unsafe Area'),
        ),
      ),
    );
  }
}

// ============================================================================
// Example 2: Dialog with Location Services Integration
// ============================================================================

class Example2_WithGeolocator extends StatefulWidget {
  const Example2_WithGeolocator({super.key});

  @override
  State<Example2_WithGeolocator> createState() =>
      _Example2_WithGeolocatorState();
}

class _Example2_WithGeolocatorState extends State<Example2_WithGeolocator> {
  double? latitude;
  double? longitude;
  bool isLoadingLocation = false;

  Future<void> _getUserLocation() async {
    setState(() => isLoadingLocation = true);
    try {
      // Example with geolocator package
      // final position = await Geolocator.getCurrentPosition();
      // setState(() {
      //   latitude = position.latitude;
      //   longitude = position.longitude;
      // });

      // Mock data for demo
      setState(() {
        latitude = 28.6;
        longitude = 77.2;
      });

      if (mounted) _showDialog();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
    } finally {
      setState(() => isLoadingLocation = false);
    }
  }

  void _showDialog() {
    if (latitude == null || longitude == null) return;

    showDialog(
      context: context,
      builder: (context) => UnsafeAreaDialog(
        latitude: latitude!,
        longitude: longitude!,
        onConfirm: (data) async {
          // Save to database
          await _saveReport(data);
        },
      ),
    );
  }

  Future<void> _saveReport(UnsafeAreaData data) async {
    print('Saving report: ${data.toJson()}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: isLoadingLocation ? null : _getUserLocation,
          child: isLoadingLocation
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Report Current Location'),
        ),
      ),
    );
  }
}

// ============================================================================
// Example 3: Dialog with Firebase Integration
// ============================================================================

class Example3_WithFirebase extends StatelessWidget {
  const Example3_WithFirebase({super.key});

  void _showDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => UnsafeAreaDialog(
        latitude: 28.6,
        longitude: 77.2,
        onConfirm: (data) async {
          await _submitToFirebase(context, data);
        },
        onCancel: () {
          print('Report cancelled');
        },
      ),
    );
  }

  Future<void> _submitToFirebase(
    BuildContext context,
    UnsafeAreaData data,
  ) async {
    try {
      // Uncomment to use Firebase
      // final user = FirebaseAuth.instance.currentUser;
      // if (user == null) throw Exception('User not authenticated');

      // await FirebaseFirestore.instance.collection('unsafe_areas').add({
      //   ...data.toJson(),
      //   'userId': user.uid,
      //   'timestamp': FieldValue.serverTimestamp(),
      //   'verified': false,
      //   'reportCount': 1,
      // });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Area reported successfully! Thank you.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => _showDialog(context),
          child: const Text('Report Unsafe Area'),
        ),
      ),
    );
  }
}

// ============================================================================
// Example 4: FAB with Dialog (Common in Map Screens)
// ============================================================================

class Example4_WithFAB extends StatelessWidget {
  const Example4_WithFAB({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Map View')),
      body: Container(color: Colors.green.shade100),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.red,
        tooltip: 'Report Unsafe Area',
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => UnsafeAreaDialog(
              latitude: 28.6,
              longitude: 77.2,
              onConfirm: (data) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Area marked unsafe'),
                    backgroundColor: Colors.red,
                  ),
                );
              },
            ),
          );
        },
        child: const Icon(Icons.warning),
      ),
    );
  }
}

// ============================================================================
// Example 5: Dialog with Predefined Data (Edit Mode)
// ============================================================================

class Example5_EditExistingReport extends StatefulWidget {
  final UnsafeAreaData existingReport;

  const Example5_EditExistingReport({super.key, required this.existingReport});

  @override
  State<Example5_EditExistingReport> createState() =>
      _Example5_EditExistingReportState();
}

class _Example5_EditExistingReportState
    extends State<Example5_EditExistingReport> {
  void _showEditDialog() {
    showDialog(
      context: context,
      builder: (context) => UnsafeAreaDialog(
        latitude: widget.existingReport.latitude,
        longitude: widget.existingReport.longitude,
        onConfirm: (updatedData) {
          print('Report updated: ${updatedData.toJson()}');
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Current Report: ${widget.existingReport.reason}'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _showEditDialog,
              child: const Text('Edit Report'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Example 6: Multiple Dialogs in Sequence
// ============================================================================

class Example6_MultipleDialogs extends StatelessWidget {
  const Example6_MultipleDialogs({super.key});

  Future<void> _showConfirmationDialog(
    BuildContext context,
    UnsafeAreaData data,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Report'),
        content: Text(
          'Report unsafe area at ${data.latitude}, ${data.longitude}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report submitted')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => UnsafeAreaDialog(
                latitude: 28.6,
                longitude: 77.2,
                onConfirm: (data) {
                  Navigator.pop(context);
                  _showConfirmationDialog(context, data);
                },
              ),
            );
          },
          child: const Text('Report with Confirmation'),
        ),
      ),
    );
  }
}

// ============================================================================
// Example 7: Dialog with Error Handling and Loading State
// ============================================================================

class Example7_WithErrorHandling extends StatefulWidget {
  const Example7_WithErrorHandling({super.key});

  @override
  State<Example7_WithErrorHandling> createState() =>
      _Example7_WithErrorHandlingState();
}

class _Example7_WithErrorHandlingState
    extends State<Example7_WithErrorHandling> {
  void _showDialog() {
    showDialog(
      context: context,
      builder: (context) => UnsafeAreaDialog(
        latitude: 28.6,
        longitude: 77.2,
        onConfirm: (data) async {
          try {
            // Validate data
            if (data.reason == null && data.timeType == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Please select at least one option'),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }

            // Show loading
            if (context.mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) =>
                    const Center(child: CircularProgressIndicator()),
              );
            }

            // Submit (simulate delay)
            await Future.delayed(const Duration(seconds: 2));

            if (context.mounted) {
              Navigator.pop(context); // Close loading dialog
              Navigator.pop(context); // Close original dialog
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Report submitted successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: _showDialog,
          child: const Text('Report with Error Handling'),
        ),
      ),
    );
  }
}
