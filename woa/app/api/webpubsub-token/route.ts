// app/api/webpubsub-token/route.ts
export const runtime = 'nodejs';

import { NextResponse } from 'next/server';
import { WebPubSubServiceClient } from '@azure/web-pubsub';

const connectionString = process.env.WEB_PUBSUB_CONNECTION_STRING;
const hubName = process.env.WEB_PUBSUB_HUB_NAME || 'woa';

export async function GET() {
  console.log('SERVER route sees:', {
    connectionString,
    hubName,
  });

  if (!connectionString) {
    return NextResponse.json(
      { error: 'Missing WEB_PUBSUB_CONNECTION_STRING environment variable' },
      { status: 500 }
    );
  }

  let serviceClient: WebPubSubServiceClient;
  try {
    serviceClient = new WebPubSubServiceClient(connectionString, hubName);
  } catch (error) {
    return NextResponse.json(
      { error: 'Failed to initialize WebPubSubServiceClient', details: String(error) },
      { status: 500 }
    );
  }

  try {
    const token = await serviceClient.getClientAccessToken({
      userId: 'app-user',
      roles: ['webpubsub.connect', 'webpubsub.sendToGroup', 'webpubsub.joinLeaveGroup'],
      groups: ['navigation', 'events', 'story', 'details'], // optional
      expirationTimeInMinutes: 60,
    });

    if (!token?.url) {
      return NextResponse.json({ error: 'No URL in token response' }, { status: 500 });
    }

    return NextResponse.json({ url: token.url });
  } catch (error) {
    return NextResponse.json(
      { error: 'Failed to get token', details: String(error) },
      { status: 500 }
    );
  }
}
