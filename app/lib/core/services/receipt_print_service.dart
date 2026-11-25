import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/order.dart';
import '../models/restaurant_settings.dart';
import '../utils/formatters.dart';

/// Genera e imprime un recibo de compra sencillo en papel continuo de 80 mm.
///
/// La generación del PDF es pura (sin canales de plataforma) para poder
/// probarla sin un dispositivo; `printReceipt` es la única parte que abre el
/// diálogo de impresión del sistema.
class ReceiptPrintService {
  const ReceiptPrintService({required this.order, required this.settings});

  final Order order;
  final RestaurantSettings settings;

  static pw.TextStyle get _small =>
      const pw.TextStyle(fontSize: 8, color: PdfColors.grey700);
  static pw.TextStyle get _section => pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
      );

  static const PdfPageFormat _receiptFormat = PdfPageFormat(
    80 * PdfPageFormat.mm,
    297 * PdfPageFormat.mm,
    marginAll: 4 * PdfPageFormat.mm,
  );

  static Future<pw.ThemeData> _buildTheme() async {
    final fontData = await rootBundle.load('assets/fonts/Geist-Regular.ttf');
    final font = pw.Font.ttf(fontData);
    return pw.ThemeData.withFont(
      base: font,
      bold: font,
      italic: font,
      boldItalic: font,
    );
  }

  Future<pw.Document> buildDocument() async {
    final document = pw.Document(theme: await _buildTheme());
    document.addPage(
      pw.MultiPage(
        pageFormat: _receiptFormat,
        margin: const pw.EdgeInsets.all(4 * PdfPageFormat.mm),
        build: (_) => <pw.Widget>[
          pw.Center(
            child: pw.Text(
              settings.name,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              'Recibo de compra',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
          if (settings.address.trim().isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Center(
              child: pw.Text(settings.address, style: _small),
            ),
          ],
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text(
              '${settings.countryCode} ${settings.phone}',
              style: _small,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Divider(),
          _row('Pedido', order.code),
          _row('Fecha', formatDateTime(order.createdAt)),
          _row('Tipo', order.type.label),
          if (order.tableNumber != null)
            _row('Mesa', '${order.tableNumber}'),
          _row('Cliente', order.customerName),
          if (order.customerPhone.trim().isNotEmpty)
            _row('Teléfono', order.customerPhone),
          if (order.deliveryAddress.trim().isNotEmpty)
            _row('Dirección', order.deliveryAddress),
          _row('Pago', order.paymentStatus.label),
          pw.Divider(),
          pw.Text('Productos', style: _section),
          pw.SizedBox(height: 3),
          ...order.items.map(
            (item) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _row('${item.quantity} x ${item.name}', formatCop(item.subtotal)),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 2, bottom: 3),
                  child: pw.Text(
                    '${formatCop(item.price)} c/u',
                    style: _small,
                  ),
                ),
              ],
            ),
          ),
          pw.Divider(),
          _row('Subtotal', formatCop(order.subtotal)),
          _row('Impuestos', formatCop(order.tax)),
          _row(
            'Total',
            formatCop(order.total),
            strong: true,
            fontSize: 11,
          ),
          if (order.payments.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text('Detalle del pago', style: _section),
            pw.SizedBox(height: 3),
            ...order.payments.map(
              (payment) => _row(payment.method.label, formatCop(payment.amount)),
            ),
            if (order.paidByNameOrFallback.isNotEmpty)
              _row('Cobrado por', order.paidByNameOrFallback),
          ],
          if (order.notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text('Notas', style: _section),
            pw.SizedBox(height: 3),
            pw.Text(order.notes, style: _small),
          ],
          pw.SizedBox(height: 10),
          pw.Divider(),
          pw.Center(
            child: pw.Text(
              '¡Gracias por su compra!',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(child: pw.Text(settings.name, style: _small)),
        ],
      ),
    );
    return document;
  }

  Future<Uint8List> buildBytes() async => (await buildDocument()).save();

  Future<void> printReceipt() async {
    final bytes = await buildBytes();
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: 'Recibo ${order.code}',
      format: _receiptFormat,
      dynamicLayout: false,
    );
  }

  static pw.Widget _row(
    String label,
    String value, {
    bool strong = false,
    double fontSize = 9,
  }) {
    final style = pw.TextStyle(
      fontSize: fontSize,
      fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Text(label, style: style),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}
