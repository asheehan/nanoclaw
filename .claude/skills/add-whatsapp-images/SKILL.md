---
name: add-whatsapp-images
description: Add WhatsApp image/media download support to NanoClaw. Automatically downloads images sent via WhatsApp and makes them available to the agent for reading and processing.
---

# Add WhatsApp Image Support

This skill adds automatic image download when users send pictures in WhatsApp. Images are downloaded, saved locally, and the file path is provided to the agent so they can be read and processed.

**UX Note:** When asking the user questions, prefer using the `AskUserQuestion` tool instead of just outputting text.

## Prerequisites

No additional dependencies required - uses existing Baileys library features.

---

## Implementation

### Step 1: Update Database Schema

Add an `image_path` column to the messages table to store downloaded image locations.

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

### Step 4: Add Image Download Handler

Download images when messages are received and save them to the sessions directory.

Update `src/index.ts` - find the `sock.ev.on('messages.upsert', ...)` handler (around line 763) and:

1. Make the callback async:
```typescript
sock.ev.on('messages.upsert', async ({ messages }) => {
```

2. Add image download logic before storing the message (insert after `storeChatMetadata` call):

```typescript
let imagePath: string | undefined;

// Download and save image if present
if (msg.message.imageMessage && registeredGroups[chatJid]) {
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
      const ext = msg.message.imageMessage.mimetype?.includes('png') ? 'png' : 'jpg';
      const filename = `${msgId}.${ext}`;
      imagePath = path.join(DATA_DIR, 'sessions', chatJid, 'media', filename);

      // Create media directory if it doesn't exist
      fs.mkdirSync(path.dirname(imagePath), { recursive: true });
      fs.writeFileSync(imagePath, buffer);

      logger.info({ chatJid, imagePath }, 'Downloaded and saved image');
    }
  } catch (err) {
    logger.error({ err, chatJid }, 'Failed to download image');
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

1. Send a picture with a caption via WhatsApp
2. Check that the image is downloaded to `data/sessions/{chat_jid}/media/`
3. Verify the agent can see the image path and use the Read tool to view it
4. Ask the agent to describe what's in the image

## Troubleshooting

- **Images not downloading**: Check logs for download errors
- **Permission errors**: Ensure the media directory is writable
- **Agent can't see images**: Verify image paths are being added to message XML
- **Missing images**: Check that `downloadMediaMessage` is being called for imageMessage types
