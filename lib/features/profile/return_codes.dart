import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

String returnEvidencePurpose(String? purpose) => switch (purpose) {
  'intake' => 'hub intake',
  'seller-receive' || 'seller_receive' => 'seller receipt',
  _ => 'return request',
};

String returnNextStep(String? status) => switch (status) {
  'requested' => 'The seller reviews your items and evidence. After the response deadline, use the available action to ask for admin review.',
  'rejected' => 'Read the seller’s recorded reason. You may ask for admin review before the appeal deadline when that action is available.',
  'escalated' => 'An admin is reviewing this request and the seller feedback. A review does not confirm repayment.',
  'approved' => 'Return transport is approved. Follow the drop-off deadline and recorded hub handovers before repayment can be reviewed.',
  'withdrawn' || 'expired' || 'denied' => 'This request is closed without repayment. Its evidence and decisions remain available.',
  'repaid' => 'Receipt of the recorded repayment was confirmed. The original purchase and payment records remain available.',
  'closed_no_repayment' => 'Original product discounts covered the returned merchandise. No merchandise repayment or outgoing transfer was due.',
  'payment_recorded' => 'Check whether you received the recorded repayment. Use the available action to confirm receipt or report a missing payment.',
  'repayment_disputed' => 'Your non-receipt report is awaiting review. The existing payment remains recorded; a second repayment is not authorized.',
  'repayment_ready' => 'The repayment amount is approved. Backing and an actual recorded transfer are required before receipt can be confirmed.',
  _ => 'Follow the parcel and payment records below. Physical receipt and repayment are separate steps.',
};

class ReturnCodes extends StatelessWidget {
  const ReturnCodes({super.key, required this.code});
  final String code;
  @override
  Widget build(BuildContext context) {
    if (code.length > 128 || !Barcode.code128().isValid(code)) {
      return const Text(
        'The return label cannot be rendered. Refresh the case or use its recorded code.',
      );
    }
    return Semantics(
      label: 'Scannable return label for $code',
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            SizedBox(
              width: 340,
              height: 80,
              child: BarcodeWidget(
                barcode: Barcode.code128(),
                data: code,
                drawText: false,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 160,
              height: 160,
              child: BarcodeWidget(
                barcode: Barcode.qrCode(),
                data: code,
                drawText: false,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(code),
          ],
        ),
      ),
    );
  }
}
