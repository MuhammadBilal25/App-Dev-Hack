'use strict';

const PDFDocument = require('pdfkit');

const money = (minor) => `PKR ${(minor / 100).toFixed(2)}`;

// Server-side PDF receipt. Text includes the order_id and the total as "PKR 4500.00". `lines`
// (optional) gives a product label per item; `signature` prints the HMAC integrity signature.
function receiptPdf(payload, { lines = null, signature = null } = {}) {
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
    payload.items.forEach((it, i) => {
      if (lines && lines[i]) doc.font('Helvetica-Bold').text(lines[i]).font('Helvetica');
      doc.text(`${it.variant_id}  x${it.quantity}  @ ${money(it.unit_price_minor)}  = ${money(it.unit_price_minor * it.quantity)}`);
    });
    doc.moveDown();
    doc.text(`Subtotal: ${money(payload.subtotal_minor)}`);
    doc.text(`Discount: ${money(payload.discount_minor)}`);
    doc.font('Helvetica-Bold').text(`Total: ${money(payload.total_minor)}`);
    if (signature) {
      doc.moveDown().font('Helvetica').fontSize(7).text('Integrity signature (HMAC-SHA256):');
      doc.text(signature);
    }
    doc.end();
  });
}

module.exports = { receiptPdf, money };
