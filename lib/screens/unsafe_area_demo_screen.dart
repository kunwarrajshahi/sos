import 'package:flutter/material.dart';
import '../widgets/unsafe_area_dialog.dart';

/// Demo screen showing how to use the UnsafeAreaDialog
class UnsafeAreaDemoScreen extends StatefulWidget {
  const UnsafeAreaDemoScreen({super.key});

  @override
  State<UnsafeAreaDemoScreen> createState() => _UnsafeAreaDemoScreenState();
}

class _UnsafeAreaDemoScreenState extends State<UnsafeAreaDemoScreen> {
  UnsafeAreaData? lastSubmittedData;

  void _showUnsafeAreaDialog() {
    showDialog(
      context: context,
      builder: (context) => UnsafeAreaDialog(
        latitude: 28.6,
        longitude: 77.2,
        onConfirm: (data) {
          setState(() {
            lastSubmittedData = data;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Area marked unsafe: ${data.toJson()}'),
              backgroundColor: Colors.red,
            ),
          );
        },
        onCancel: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Dialog cancelled')));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unsafe Area Dialog Demo'),
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Column(
                  spacing: 16,
                  children: [
                    Icon(Icons.warning_rounded, size: 48, color: Colors.red),
                    const Text(
                      'Report Unsafe Area',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const Text(
                      'Help other users by marking unsafe areas in your neighborhood',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _showUnsafeAreaDialog,
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 14,
                        ),
                      ),
                      child: const Text('Open Dialog'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              if (lastSubmittedData != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 12,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green),
                          const SizedBox(width: 8),
                          const Text(
                            'Last Submission',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      _buildInfoRow(
                        'Location',
                        '${lastSubmittedData!.latitude}, ${lastSubmittedData!.longitude}',
                      ),
                      if (lastSubmittedData!.reason != null)
                        _buildInfoRow('Reason', lastSubmittedData!.reason!),
                      if (lastSubmittedData!.timeType != null)
                        _buildInfoRow(
                          'Time Type',
                          lastSubmittedData!.timeType!,
                        ),
                      if (lastSubmittedData!.timeStart != null)
                        _buildInfoRow(
                          'Time Range',
                          '${lastSubmittedData!.timeStart} - ${lastSubmittedData!.timeEnd}',
                        ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Submit a report to see the data here',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          ),
        ),
      ],
    );
  }
}
