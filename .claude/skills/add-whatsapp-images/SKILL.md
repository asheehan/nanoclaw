---
name: add-whatsapp-images
description: Add WhatsApp media download support to NanoClaw. Automatically downloads images, videos, and documents sent via WhatsApp and makes them available to the agent for reading and processing.
---

# Add WhatsApp Media Support

This skill adds automatic media download when users send pictures, videos, or documents in WhatsApp. Media is downloaded, saved locally, and the file path is provided to the agent so they can be read and processed.

**Important**: WhatsApp sends images in different formats depending on how they're sent:
- `imageMessage` - inline images (less common)
- `documentMessage` - images sent as files (most common)
- `videoMessage` - videos

This implementation handles all three formats.

**UX Note:** When asking the user questions, prefer using the `AskUserQuestion` tool instead of just outputting text.

## Prerequisites

No additional dependencies required - uses existing Baileys library features.

---

## Implementation

### Step 1: Update Database Schema

Add an `image_path` column to the messages table to store downloaded media locations.

Update `src/db.ts` - add migration after the existing column migrations (around line 88):

```typescript
// Add image_path column if it doesn't exist (migration for existing DBs)
try {
  db.exec(`ALTER TABLE messages ADD COLUMN image_path TEXT`);
} catch {
  /* column already exists */
}
```

### Step 2: Update NewMessage Type

Add the image_path field to the message interface.

Update `src/types.ts` - modify the NewMessage interface:

```typescript
export interface NewMessage {
  id: string;
  chat_jid: string;
  sender: string;
  sender_name: string;
  content: string;
  timestamp: string;
  image_path?: string;  // Add this line
}
```

### Step 3: Import Download Function

Add the media download function from Baileys.

Update `src/index.ts` - modify the import statement at the top:

```typescript
import makeWASocket, {
  DisconnectReason,
  WASocket,
  makeCacheableSignalKeyStore,
  useMultiFileAuthState,
  downloadMediaMessage,  // Add this import
} from '@whiskeysockets/baileys';
```

### Step 4: Add Media Download Handler

Download media when messages are received and save them to the sessions directory.

Update `src/index.ts` - find the `sock.ev.on('messages.upsert', ...)` handler (around line 767) and:

1. Make the callback async:
```typescript
sock.ev.on('messages.upsert', async ({ messages }) => {
```

2. Add media download logic before storing the message (insert after `storeChatMetadata` call):

```typescript
let imagePath: string | undefined;

// Download and save media if present (images, videos, or documents with image mimetypes)
const hasMedia = msg.message.imageMessage || msg.message.videoMessage || msg.message.documentMessage;
if (hasMedia && registeredGroups[chatJid]) {
  const mediaType = msg.message.imageMessage ? 'image' :
                   msg.message.videoMessage ? 'video' : 'document';
  logger.info({ chatJid, mediaType }, 'Attempting to download media...');
  try {
    const buffer = await downloadMediaMessage(
      msg,
      'buffer',
      {},
      {
        logger: logger.child({ module: 'media-download' }),
        reuploadRequest: sock.updateMediaMessage,
      }
    );

    if (buffer) {
      const msgId = msg.key.id || Date.now().toString();
      // Get extension from mimetype or default based on message type
      let ext = 'bin';
      const mimetype = msg.message.imageMessage?.mimetype ||
                     msg.message.videoMessage?.mimetype ||
                     msg.message.documentMessage?.mimetype;
      if (mimetype) {
        if (mimetype.includes('png')) ext = 'png';
        else if (mimetype.includes('jpeg') || mimetype.includes('jpg')) ext = 'jpg';
        else if (mimetype.includes('gif')) ext = 'gif';
        else if (mimetype.includes('mp4')) ext = 'mp4';
        else if (mimetype.includes('pdf')) ext = 'pdf';
      }
      const filename = `${msgId}.${ext}`;
      imagePath = path.join(DATA_DIR, 'sessions', chatJid, 'media', filename);

      // Create media directory if it doesn't exist
      fs.mkdirSync(path.dirname(imagePath), { recursive: true });
      fs.writeFileSync(imagePath, buffer);

      logger.info({ chatJid, imagePath, mimetype }, 'Downloaded and saved media');
    }
  } catch (err) {
    logger.error({ err, chatJid }, 'Failed to download media');
  }
}
```

3. Update the storeMessage call to include the image path:

```typescript
storeMessage(
  msg,
  chatJid,
  msg.key.fromMe || false,
  msg.pushName || undefined,
  imagePath,  // Add this parameter
);
```

### Step 5: Update storeMessage Function

Modify the storeMessage function to accept and store the image path.

Update `src/db.ts` - find the `storeMessage` function (around line 207) and:

1. Add imagePath parameter:
```typescript
export function storeMessage(
  msg: proto.IWebMessageInfo,
  chatJid: string,
  isFromMe: boolean,
  pushName?: string,
  imagePath?: string,  // Add this parameter
): void {
```

2. Update the SQL INSERT to include image_path:
```typescript
db.prepare(
  `INSERT OR REPLACE INTO messages (id, chat_jid, sender, sender_name, content, timestamp, is_from_me, image_path) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
).run(
  msgId,
  chatJid,
  sender,
  senderName,
  content,
  timestamp,
  isFromMe ? 1 : 0,
  imagePath || null,  // Add this parameter
);
```

### Step 6: Update getNewMessages to Return Image Paths

Modify the SQL query to select the image_path column.

Update `src/db.ts` - find the `getNewMessages` function (around line 248) and update the SQL:

```typescript
const sql = `
  SELECT id, chat_jid, sender, sender_name, content, timestamp, image_path
  FROM messages
  WHERE timestamp > ? AND chat_jid IN (${placeholders}) AND content NOT LIKE ?
  ORDER BY timestamp
`;
```

### Step 7: Include Image Paths in Message Context

Update message formatting to include image paths so the agent can read them.

Update `src/index.ts` - find where messages are formatted (around line 221) and update:

```typescript
const lines = missedMessages.map((m) => {
  const escapeXml = (s: string) =>
    s
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');

  // If there's an image, include the path so the agent can read it
  const imagePath = m.image_path ? ` image="${escapeXml(m.image_path)}"` : '';
  return `<message sender="${escapeXml(m.sender_name)}" time="${m.timestamp}"${imagePath}>${escapeXml(m.content)}</message>`;
});
```

### Step 8: Build and Test

Rebuild the TypeScript code:

```bash
npm run build
```

The service will need to restart to pick up the changes. Once restarted, the agent will receive image paths in messages like:

```xml
<message sender="User Name" time="2026-02-08T12:00:00Z" image="/path/to/image.jpg">Caption text</message>
```

The agent can then use the `Read` tool to view and analyze the image.

---

## Testing

1. Send a picture via WhatsApp (with or without a caption)
2. Check the logs for: `Attempting to download media...` and `Downloaded and saved media`
3. Verify the media is saved to `data/sessions/{chat_jid}/media/`
4. Check that the agent can see the image path in the message
5. Ask the agent to describe what's in the image using the Read tool

---

## Troubleshooting

### Media not downloading

**Check message type**: Add diagnostic logging to see what message types WhatsApp is sending:

```typescript
// Add this right after translating chatJid in the messages.upsert handler:
logger.info({
  chatJid,
  messageKeys: Object.keys(msg.message),
  hasImage: !!msg.message.imageMessage,
  hasVideo: !!msg.message.videoMessage,
  hasDocument: !!msg.message.documentMessage,
  isRegistered: !!registeredGroups[chatJid],
}, 'Message received');
```

This will show you exactly what format WhatsApp is using. Most images come through as `documentMessage`, not `imageMessage`.

**Common issues**:
- No `Attempting to download media...` log → Message type not detected, check diagnostic logs above
- `Failed to download media` error → Check error details in logs, may be network or permission issue
- Permission errors → Ensure the `data/sessions/{chat_jid}/media/` directory is writable
- Missing mimetype → Some media may not have mimetype set, defaults to `.bin` extension

### Agent can't see images

- Verify image paths are being added to message XML (check container input JSON)
- Ensure the path is accessible from within the agent container
- Check that the `image` attribute is properly escaped in XML

### Images download but wrong extension

The extension detection logic checks mimetypes. If images have the wrong extension:
1. Check the mimetype in logs: `Downloaded and saved media` log includes `mimetype`
2. Add more mimetype patterns to the extension detection logic
3. Consider adding file signature detection for better accuracy

---

## Notes for Upstream

**Why documentMessage?** - WhatsApp's mobile apps often send images as documents rather than inline images. This implementation handles all three message types to ensure compatibility across different WhatsApp client behaviors.

**Performance** - Media download happens synchronously in the message handler. For high-volume groups, consider implementing async download queues.

**Storage** - Media files accumulate in `data/sessions/{chat_jid}/media/`. Consider implementing cleanup policies for old media.
