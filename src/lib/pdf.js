'use strict';

const PDFDocument = require('pdfkit');

const money = (minor) => `PKR ${(minor / 100).toFixed(2)}`;

// Server-side PDF receipt. Text includes the order_id and the total as "PKR 4500.00".
function receiptPdf(payload) {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ size: 'A5', margin: 36, info: { Title: `Receipt ${payload.order_id}` } });
    const chunks = [];
    doc.on('data', (c) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    doc.font('Helvetica-Bold').fontSize(16).text('NaSCon League Store - Receipt');
    doc.moveDown(0.5).font('Helvetica').fontSize(10);
    doc.text(`Order: ${payload.order_id}`);
    doc.text(`Customer: ${payload.customer_id}`);
    doc.text(`Paid at: ${payload.paid_at}`);
    doc.moveDown();
    for (const it of payload.items) {
      doc.text(`${it.variant_id}  x${it.quantity}  @ ${money(it.unit_price_minor)}  = ${money(it.unit_price_minor * it.quantity)}`);
    }
    doc.moveDown();
    doc.text(`Subtotal: ${money(payload.subtotal_minor)}`);
    doc.text(`Discount: ${money(payload.discount_minor)}`);
    doc.font('Helvetica-Bold').text(`Total: ${money(payload.total_minor)}`);
    doc.end();
  });
}

module.exports = { receiptPdf, money };
