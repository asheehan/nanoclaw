---
name: add-office-support
description: Add support for reading Microsoft Office documents (Excel, Word, PowerPoint) sent via WhatsApp. Extends the media download feature to properly detect Office file extensions and provides tools to read their contents.
---

# Add Office Document Support

This skill extends NanoClaw's media download feature to handle Microsoft Office documents (Excel, Word, PowerPoint) sent via WhatsApp. It adds proper file extension detection and provides libraries for reading Office document contents.

**Prerequisites**: This skill requires the `add-whatsapp-images` skill to be installed first, as it builds on the media download functionality.

## What This Adds

- **Extension Detection**: Properly identifies .xlsx, .docx, .pptx files from mimetypes
- **Excel Reading**: Converts Excel spreadsheets to JSON/CSV format
- **Word Reading**: Extracts text and markdown from Word documents
- **PowerPoint Support**: Basic support for PowerPoint files (extension detection)

---

## Implementation

### Step 1: Update Extension Detection

Add Office document mimetypes to the extension detection logic.

Update `src/index.ts` - find the extension detection code in the media download handler (around line 112) and update it:

```typescript
// Get extension from mimetype or default based on message type
let ext = 'bin';
const mimetype = msg.message.imageMessage?.mimetype ||
               msg.message.videoMessage?.mimetype ||
               msg.message.documentMessage?.mimetype;
if (mimetype) {
  // Images
  if (mimetype.includes('png')) ext = 'png';
  else if (mimetype.includes('jpeg') || mimetype.includes('jpg')) ext = 'jpg';
  else if (mimetype.includes('gif')) ext = 'gif';
  else if (mimetype.includes('webp')) ext = 'webp';
  // Videos
  else if (mimetype.includes('mp4')) ext = 'mp4';
  else if (mimetype.includes('webm')) ext = 'webm';
  // Documents
  else if (mimetype.includes('pdf')) ext = 'pdf';
  // Office documents
  else if (mimetype.includes('spreadsheetml.sheet') || mimetype.includes('ms-excel')) ext = 'xlsx';
  else if (mimetype.includes('wordprocessingml.document') || mimetype.includes('msword')) ext = 'docx';
  else if (mimetype.includes('presentationml.presentation') || mimetype.includes('ms-powerpoint')) ext = 'pptx';
  // Archives
  else if (mimetype.includes('zip')) ext = 'zip';
  else if (mimetype.includes('rar')) ext = 'rar';
}
```

### Step 2: Rebuild and Test Extension Detection

```bash
npm run build
```

Restart the service and send an Excel, Word, or PowerPoint file via WhatsApp. Check the logs to verify the correct extension is being used:

```bash
tail -f logs/nanoclaw.log | grep "Downloaded and saved media"
```

You should see files with `.xlsx`, `.docx`, or `.pptx` extensions.

---

## Step 3: Add Excel Reading Support (Optional)

If you want the agent to be able to read Excel file contents, install the `xlsx` library:

### In the Main Project

```bash
npm install xlsx
```

### Create Excel Reader Script

Create a helper script at `scripts/read-excel.js`:

```javascript
#!/usr/bin/env node
const XLSX = require('xlsx');
const fs = require('fs');

const filePath = process.argv[2];
if (!filePath) {
  console.error('Usage: node read-excel.js <path-to-xlsx>');
  process.exit(1);
}

try {
  const workbook = XLSX.readFile(filePath);

  console.log('# Excel File Contents\n');
  console.log(`Sheets: ${workbook.SheetNames.join(', ')}\n`);

  workbook.SheetNames.forEach(sheetName => {
    console.log(`## Sheet: ${sheetName}\n`);
    const sheet = workbook.Sheets[sheetName];
    const data = XLSX.utils.sheet_to_json(sheet, { header: 1 });

    // Convert to markdown table
    if (data.length > 0) {
      // Header
      console.log('| ' + data[0].join(' | ') + ' |');
      console.log('|' + data[0].map(() => '---').join('|') + '|');

      // Rows
      data.slice(1).forEach(row => {
        console.log('| ' + row.join(' | ') + ' |');
      });
      console.log('\n');
    }
  });
} catch (err) {
  console.error('Error reading Excel file:', err.message);
  process.exit(1);
}
```

Make it executable:

```bash
chmod +x scripts/read-excel.js
```

### Usage

The agent can now read Excel files using:

```bash
node scripts/read-excel.js /path/to/file.xlsx
```

---

## Step 4: Add Word Reading Support (Optional)

If you want the agent to be able to read Word document contents:

### Install Mammoth

```bash
npm install mammoth
```

### Create Word Reader Script

Create a helper script at `scripts/read-word.js`:

```javascript
#!/usr/bin/env node
const mammoth = require('mammoth');
const fs = require('fs');

const filePath = process.argv[2];
if (!filePath) {
  console.error('Usage: node read-word.js <path-to-docx>');
  process.exit(1);
}

mammoth.extractRawText({ path: filePath })
  .then(result => {
    console.log('# Word Document Contents\n');
    console.log(result.value);

    if (result.messages.length > 0) {
      console.error('\n## Warnings:');
      result.messages.forEach(m => console.error(`- ${m.message}`));
    }
  })
  .catch(err => {
    console.error('Error reading Word document:', err.message);
    process.exit(1);
  });
```

Make it executable:

```bash
chmod +x scripts/read-word.js
```

### Usage

The agent can now read Word documents using:

```bash
node scripts/read-word.js /path/to/file.docx
```

---

## Testing

### Test Extension Detection

1. Send an Excel file via WhatsApp
2. Check logs: `tail -f logs/nanoclaw.log | grep "Downloaded and saved media"`
3. Verify the file has `.xlsx` extension, not `.bin`
4. Repeat for Word (`.docx`) and PowerPoint (`.pptx`) files

### Test Excel Reading (if installed)

1. Send an Excel file with some data
2. Agent receives the file path in the message
3. Agent runs: `node scripts/read-excel.js /path/to/file.xlsx`
4. Agent can see the spreadsheet data as markdown tables

### Test Word Reading (if installed)

1. Send a Word document
2. Agent receives the file path
3. Agent runs: `node scripts/read-word.js /path/to/file.docx`
4. Agent can read the document text

---

## Troubleshooting

### Wrong Extensions Still Appearing

**Issue**: Files still have `.bin` extension after updating code

**Solution**:
1. Check that you rebuilt with `npm run build`
2. Verify the service restarted and loaded new code
3. Check logs for the mimetype: `grep "Downloaded and saved media" logs/nanoclaw.log`
4. The mimetype should contain `spreadsheetml` for Excel, `wordprocessingml` for Word

### Excel/Word Scripts Not Working

**Issue**: `Cannot find module 'xlsx'` or `Cannot find module 'mammoth'`

**Solution**:
1. Make sure you ran `npm install` in the **project root**, not in a group folder
2. Verify packages are in `node_modules/`: `ls node_modules/ | grep -E "xlsx|mammoth"`
3. If missing, run: `cd /path/to/nanoclaw && npm install xlsx mammoth`

### Agent Can't Execute Scripts

**Issue**: `permission denied` when running scripts

**Solution**:
```bash
chmod +x scripts/read-excel.js
chmod +x scripts/read-word.js
```

### PowerPoint Files

**Note**: PowerPoint file reading is more complex. The skill provides extension detection for `.pptx` files, but reading their contents requires additional libraries like `pptxgenjs` or `officegen`. Consider adding this in a future enhancement if needed.

---

## Notes for Upstream

**Mimetype Coverage**: The Office mimetype detection covers both modern Office formats (Office 2007+) and legacy formats:
- Excel: `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` and `application/vnd.ms-excel`
- Word: `application/vnd.openxmlformats-officedocument.wordprocessingml.document` and `application/msword`
- PowerPoint: `application/vnd.openxmlformats-officedocument.presentationml.presentation` and `application/vnd.ms-powerpoint`

**Dependencies**: The Excel and Word reading scripts are optional. The core skill (extension detection) has no additional dependencies.

**Alternative Approaches**: Instead of Bash scripts, you could implement Office reading directly in TypeScript/JavaScript within the agent container. The scripts approach is simpler but requires the agent to use the Bash tool.
