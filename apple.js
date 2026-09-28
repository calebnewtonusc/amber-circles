// Verifies a Sign in with Apple identity token against Apple's published
// keys: signature (RS256), issuer, audience (our two bundle ids) and expiry.
// A phone saying "I am this Apple user" is not trusted on its word.
import { createPublicKey, createVerify } from "node:crypto";

const AUDIENCES = new Set(["com.calebnewton.amber", "com.calebnewton.amber.messages"]);
let keys = null;
let fetchedAt = 0;

async function appleKeys() {
  // Apple rotates these rarely; an hour of cache keeps sign-in fast.
  if (!keys || Date.now() - fetchedAt > 3600_000) {
    const response = await fetch("https://appleid.apple.com/auth/keys");
    keys = (await response.json()).keys;
    fetchedAt = Date.now();
  }
  return keys;
}

const decode = (part) => {
  try {
    return JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
  } catch {
    throw new Error("That sign-in did not come through. Try again.");
  }
};

export async function verifyAppleToken(token) {
  const [head, body, signature] = String(token || "").split(".");
  if (!head || !body || !signature) throw new Error("That sign-in did not come through. Try again.");
  const header = decode(head);
  const claims = decode(body);
  const jwk = (await appleKeys()).find((key) => key.kid === header.kid);
  if (!jwk || header.alg !== "RS256") throw new Error("That sign-in was not from Apple.");
  const verifier = createVerify("RSA-SHA256");
  verifier.update(`${head}.${body}`);
  if (!verifier.verify(createPublicKey({ key: jwk, format: "jwk" }), Buffer.from(signature, "base64url")))
    throw new Error("That sign-in was not from Apple.");
  if (claims.iss !== "https://appleid.apple.com" || !AUDIENCES.has(claims.aud))
    throw new Error("That sign-in was for a different app.");
  if (claims.exp * 1000 < Date.now()) throw new Error("That sign-in expired. Try again.");
  return { sub: claims.sub };
}
