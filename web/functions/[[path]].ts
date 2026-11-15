import { createPagesFunctionHandler } from "@react-router/cloudflare";

// @ts-expect-error - virtual module provided by React Router at build time
import * as build from "../build/server";

export const onRequest = createPagesFunctionHandler({ build });
