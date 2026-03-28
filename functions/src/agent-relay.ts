import { https } from "firebase-functions/v2";
import { logger } from "firebase-functions";
import { CLOUD_RUN_AGENT_URL } from "./config";

interface AgentRequest {
  message: string;
  sessionId?: string;
  context?: {
    lat?: number;
    lng?: number;
    activeAlertId?: string;
  };
}

interface AgentResponse {
  reply: string;
  sessionId: string;
  actions?: Array<{
    type: string;
    payload: Record<string, unknown>;
  }>;
}

/**
 * HTTP callable that relays authenticated requests from the iOS app
 * to the Cloud Run AI Agent service. Verifies the Firebase JWT and
 * forwards the user context to the agent.
 */
export const relayToAgent = https.onCall(
  {
    enforceAppCheck: true,
    timeoutSeconds: 60,
    memory: "256MiB",
  },
  async (request): Promise<AgentResponse> => {
    if (!request.auth) {
      throw new https.HttpsError(
        "unauthenticated",
        "Must be signed in to use the AI agent"
      );
    }

    const data = request.data as AgentRequest;

    if (!data.message || data.message.trim().length === 0) {
      throw new https.HttpsError(
        "invalid-argument",
        "message is required"
      );
    }

    const uid = request.auth.uid;
    const email = request.auth.token.email ?? "";
    const name = request.auth.token.name ?? "";

    logger.info("Relaying to agent", {
      uid,
      sessionId: data.sessionId,
      messageLength: data.message.length,
    });

    const agentPayload = {
      message: data.message,
      session_id: data.sessionId,
      user: {
        uid,
        email,
        name,
      },
      context: data.context ?? {},
    };

    try {
      const baseUrl = CLOUD_RUN_AGENT_URL.value();
      if (!baseUrl) {
        throw new https.HttpsError(
          "unavailable",
          "AI agent service is not configured yet"
        );
      }
      const agentUrl = `${baseUrl}/chat`;

      const response = await fetch(agentUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Firebase-UID": uid,
        },
        body: JSON.stringify(agentPayload),
      });

      if (!response.ok) {
        const errorBody = await response.text();
        logger.error("Agent service returned error", {
          status: response.status,
          body: errorBody,
        });
        throw new https.HttpsError(
          "internal",
          `Agent service error: ${response.status}`
        );
      }

      const result = (await response.json()) as AgentResponse;

      logger.info("Agent response received", {
        uid,
        sessionId: result.sessionId,
        hasActions: (result.actions?.length ?? 0) > 0,
      });

      return result;
    } catch (error) {
      if (error instanceof https.HttpsError) throw error;

      logger.error("Failed to relay to agent", { uid, error });
      throw new https.HttpsError(
        "unavailable",
        "AI agent is temporarily unavailable. Please try again."
      );
    }
  }
);

/**
 * Lightweight health-check endpoint for the agent relay.
 * The iOS app can ping this to verify connectivity.
 */
export const agentHealthCheck = https.onRequest(
  { timeoutSeconds: 10 },
  async (_req, res) => {
    try {
      const baseUrl = CLOUD_RUN_AGENT_URL.value();
      if (!baseUrl) {
        res.json({
          relay: "ok",
          agent: "not_configured",
          timestamp: new Date().toISOString(),
        });
        return;
      }
      const agentUrl = `${baseUrl}/health`;
      const response = await fetch(agentUrl, { method: "GET" });

      res.json({
        relay: "ok",
        agent: response.ok ? "ok" : "degraded",
        agentStatus: response.status,
        timestamp: new Date().toISOString(),
      });
    } catch {
      res.json({
        relay: "ok",
        agent: "unreachable",
        timestamp: new Date().toISOString(),
      });
    }
  }
);
