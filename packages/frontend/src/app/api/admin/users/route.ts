import { eq } from "drizzle-orm";
import { NextResponse } from "next/server";

import { getSession, getSessionFromHeader } from "@/lib/auth/session";
import { hashToken } from "@/lib/auth/utils";
import { apiTokens, db, users } from "@/lib/db";

export async function POST(request: Request) {
  const session =
    (await getSessionFromHeader(request)) ?? (await getSession());

  if (!session?.isAdmin) {
    return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  }

  const body = await request.json();
  const { username, displayName, isAdmin = false, createToken = false } = body;

  if (!username || typeof username !== "string") {
    return NextResponse.json(
      { error: "username is required" },
      { status: 400 }
    );
  }

  if (!/^[a-zA-Z0-9-]+$/.test(username) || username.length > 39) {
    return NextResponse.json(
      { error: "username must be alphanumeric/hyphens, max 39 chars" },
      { status: 400 }
    );
  }

  const existing = await db
    .select({ id: users.id })
    .from(users)
    .where(eq(users.username, username))
    .limit(1);

  type UserResult = {
    id: string;
    username: string;
    displayName: string | null;
    isAdmin: boolean;
    createdAt: Date;
  };

  let user: UserResult;

  if (existing.length > 0) {
    [user] = await db
      .update(users)
      .set({
        displayName: displayName || username,
        isAdmin,
        updatedAt: new Date(),
      })
      .where(eq(users.id, existing[0].id))
      .returning({
        id: users.id,
        username: users.username,
        displayName: users.displayName,
        isAdmin: users.isAdmin,
        createdAt: users.createdAt,
      });
  } else {
    const fakeGithubId = Math.abs(hashCode(username));

    [user] = await db
      .insert(users)
      .values({
        githubId: fakeGithubId,
        username,
        displayName: displayName || username,
        isAdmin,
      })
      .returning({
        id: users.id,
        username: users.username,
        displayName: users.displayName,
        isAdmin: users.isAdmin,
        createdAt: users.createdAt,
      });
  }

  let token: string | undefined;

  if (createToken) {
    token = `tt_${username}`;
    const tokenHashed = hashToken(token);

    await db
      .delete(apiTokens)
      .where(eq(apiTokens.userId, user.id));

    await db.insert(apiTokens).values({
      userId: user.id,
      token: tokenHashed,
      name: "default",
    });
  }

  const status = existing.length > 0 ? 200 : 201;
  return NextResponse.json({ user, token }, { status });
}

function hashCode(str: string): number {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = (Math.imul(31, hash) + str.charCodeAt(i)) | 0;
  }
  return hash;
}
