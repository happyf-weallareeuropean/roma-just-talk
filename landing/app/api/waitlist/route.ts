import { sql } from "drizzle-orm";
import { getDb } from "../../../db";
import { waitlistSignups } from "../../../db/schema";

function toRouteErrorMessage(error: unknown) {
  const message = error instanceof Error ? error.message : "Unexpected error";
  const detail =
    error instanceof Error && error.cause instanceof Error ? error.cause.message : "";
  const combined = `${message}\n${detail}`;

  if (combined.includes("no such table") || combined.includes("waitlist_signups")) {
    return "The waitlist table is unavailable. Run `npm run db:generate`, then deploy with the generated D1 migration.";
  }

  return message;
}

export async function POST(request: Request) {
  try {
    const payload = (await request.json()) as {
      email?: string;
      sourceOs?: string;
    };
    const email = payload.email?.trim().toLowerCase() ?? "";
    const sourceOs = payload.sourceOs?.trim().toLowerCase() || "windows";

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return Response.json({ error: "valid email required" }, { status: 400 });
    }

    const db = getDb();
    const userAgent = request.headers.get("user-agent") ?? "";

    const [signup] = await db
      .insert(waitlistSignups)
      .values({ email, sourceOs, userAgent })
      .onConflictDoUpdate({
        target: waitlistSignups.email,
        set: {
          sourceOs,
          userAgent,
          updatedAt: sql`CURRENT_TIMESTAMP`,
        },
      })
      .returning();

    return Response.json({ signup }, { status: 201 });
  } catch (error) {
    return Response.json(
      { error: toRouteErrorMessage(error) },
      { status: 500 }
    );
  }
}
