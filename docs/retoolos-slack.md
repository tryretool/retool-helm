# Connect Retool agents to Slack (Helm)

This setup uses one Slack app owned by your organization for all Retool agents. Each person who messages the bot talks to their own agent. Your Retool administrator installs the app once for the organization; you do not need a Slack app per agent.

## 1. Configure the Slack app

Create a Slack app in the workspace where it will be used. In **App Home**, enable the **Messages** tab so people can DM the bot. You can also enable Slack's **Agents** feature for an agent-specific experience, including Retool's "is thinking..." indicator. Basic DM conversations still work without that feature. See Slack's [App Home](https://docs.slack.dev/surfaces/app-home/) and [agent](https://docs.slack.dev/ai/developing-agents/) setup guides.

In **OAuth & Permissions**, add these **bot token scopes**: `assistant:write`, `chat:write`, `im:history`, `im:write`, `users:read`, and `users:read.email`. Retool requests and checks all six during installation, including `assistant:write` even if you do not enable Slack's Agents feature.

Register this OAuth redirect URL, using the HTTPS address where your administrators access Retool:

```text
https://<your-retool-host>/api/os/messaging/slack/oauth/callback
```

The redirect must match the URL Retool sends to Slack, including its scheme and host. After approval, Slack redirects the administrator's **browser** to this URL. The browser must be able to reach it in either mode; VPN-only access is fine. Socket Mode does not remove this OAuth callback.

Then choose one inbound transport:

**HTTP mode:** Enable Event Subscriptions, subscribe to the `message.im` bot event, and set the request URL to `https://<your-retool-host>/api/os/messaging/slack/events`. Enable Interactivity and set its request URL to `https://<your-retool-host>/api/os/messaging/slack/interactions`. Slack must be able to reach both HTTPS endpoints on the Retool backend.

**Socket Mode:** Enable Socket Mode, Event Subscriptions with the `message.im` bot event, and Interactivity. Generate an app-level token with the `connections:write` scope. Do not configure HTTP event or interactivity request URLs. Instead, the RetoolOS worker makes an outbound WebSocket connection to Slack; Slack does not need inbound access to these endpoints. See Slack's [Socket Mode guide](https://docs.slack.dev/apis/events-api/using-socket-mode/).

The Retool backend and worker also need outbound access to Slack's API in both modes. Socket Mode changes event delivery, not OAuth installation or outgoing bot messages.

## 2. Provide credentials through a Kubernetes Secret

Create a Secret in the Helm release's namespace using your normal secret-management process. It needs these exact keys:

| Key              | Source                        | Used by                                                                |
| ---------------- | ----------------------------- | ---------------------------------------------------------------------- |
| `client-id`      | Slack app's client ID         | Retool backend                                                         |
| `client-secret`  | Slack app's client secret     | Retool backend                                                         |
| `signing-secret` | Slack app's signing secret    | Retool backend (stored with the installation for signed HTTP requests) |
| `app-token`      | Slack app-level `xapp-` token | RetoolOS worker, `socket` mode only                                    |

Do not put the credential values in Helm values or Git. Do not provide a bot `xoxb-` token: Retool receives and stores that token when the administrator installs the app through OAuth.

Set the chart values to point at the Secret:

```yaml
retoolos:
  enabled: true
  slack:
    mode: http # or socket
    secretName: retoolos-slack
```

The chart defaults to `mode: disabled`, so RetoolOS can run without Slack. An enabled mode requires `retoolos.enabled: true` and a Secret name. In `http` mode, the chart does **not** pass `app-token` to the worker; in `socket` mode, Kubernetes requires that key when starting it. The chart does not create the Secret or verify that Slack's app settings match the selected mode. Avoid supplying `RETOOLOS_SLACK_*` variables through the generic environment settings as well: those can bypass the selected mode or duplicate the chart-generated variables.

## 3. Install and test

After upgrading, go to **Retool Settings → RetoolOS → Configure → Messaging** and select **Add to Slack**. An organization administrator completes the Slack OAuth approval there; installing the app only from Slack does not connect it to Retool. Send the bot a direct message from a Slack user whose email matches an enabled Retool user, and verify a reply. In HTTP mode, verify that Slack accepts the event and interactivity URLs. In Socket Mode, check that the RetoolOS worker establishes its Slack connection; an invalid app token is logged but does not stop the worker's other workloads.

If you rotate credentials in Slack, update the Kubernetes Secret and restart the affected Retool pods: environment variables in running pods do not update when the Secret changes. If you rotate the **signing secret**, remove and reconnect the Slack app in Retool as well. Retool stores a copy of that secret with the installation for verifying HTTP requests, so changing only the Kubernetes Secret leaves the stored copy stale.
