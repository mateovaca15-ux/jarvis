# JARVIS gratis: Oracle Cloud Always Free + Kapso Free

Esta guía reemplaza el paso 2 del README (DigitalOcean, ~US$24/mes) por una VM gratis de Oracle. Lo demás del README
sigue igual, con los cambios que se indican abajo.

| Pieza | Costo |
|---|---|
| Oracle Cloud Always Free (VM ARM) | US$0 |
| Kapso Free (1 número, 2.000 mensajes/mes) | US$0 |
| Meta: respuestas dentro de las 24 h desde tu último mensaje | US$0 |
| Voz del HUD con Microsoft (`edge-tts`) | US$0 |
| Claude Pro o Max | el plan que ya tienes |

## 1. La VM

1. Crea una cuenta en oracle.com/cloud/free. Pide tarjeta, pero no cobra. **No conviertas la cuenta a "Pay As You Go".**
2. **Compute → Instances → Create instance:**
   - Image: **Canonical Ubuntu 24.04**.
   - Shape: **VM.Standard.A1.Flex**, 2 OCPU y 12 GB (el límite gratis es 4 OCPU y 24 GB en total).
   - Sube tu llave SSH pública.
   - Si dice *Out of capacity*, prueba otro *availability domain* o vuelve a intentar más tarde.
3. **Networking → Virtual cloud networks → tu VCN → Security Lists → Default → Add Ingress Rules:**
   Source `0.0.0.0/0`, TCP, puerto `80`. Repite para el `443`.

## 2. El servidor

```bash
IP=<la IP pública de la VM>
scp deploy/setup-oracle.sh ubuntu@$IP:
ssh ubuntu@$IP "sudo bash setup-oracle.sh ${IP//./-}.sslip.io"
```

`setup-oracle.sh` es `setup.sh` con 4 cambios para Oracle:

- Chromium por snap en ARM (Google Chrome no tiene versión arm64).
- `yt-dlp` para aarch64.
- La llave SSH del usuario `assistant` sale de `ubuntu` (la de `root` en Oracle solo dice "login as ubuntu").
- Abre 80/443 con `iptables` en vez de `ufw` (la imagen de Oracle bloquea todo menos SSH, y Oracle no recomienda ufw).

Comprueba que el HTTPS funciona: `curl -s https://${IP//./-}.sslip.io/health` → `ok` (después del paso 5 del README).

## 3. El resto del README

Sigue los pasos 3 a 7 con estos cambios:

- Donde dice `ssh root@$IP "..."`, usa `ssh ubuntu@$IP "sudo ..."`.
- En `kapso.env`:

  ```
  PERMISSIONS=allowlist
  TZ_NAME=<tu zona horaria, por ejemplo America/Bogota>
  CLAUDE_MODEL=sonnet
  ```

  - `allowlist` solo deja leer y editar el vault, el calendario y leer Gmail o crear borradores. No puede mandar
    correos ni correr comandos. Pasa a `full` solo cuando confíes en él, y revisa `FORBIDDEN_TOOLS` en `server.mjs`.
  - `sonnet` gasta menos de tu plan. El valor por defecto (`opus[1m]`) agota el límite de Pro rápido. Con Max puedes
    dejar el valor por defecto.
  - Con `allowlist` no puede correr `whisper-cli` ni `yt-dlp`, así que los resúmenes de podcasts no funcionan.

## 4. Para que siga siendo gratis

- **Escríbele al bot al menos 1 vez al día.** Dentro de las 24 h desde tu último mensaje, WhatsApp deja responder
  libremente. Fuera de esa ventana, los avisos usan la plantilla `agenda_aviso`, y Meta puede cobrar por ellas.
  Revisa la tabla de precios de Meta: cambia seguido.
- **Kapso Free son 2.000 mensajes al mes**, unos 65 por día. Alcanza para uso personal.
- **Oracle puede recuperar VMs Always Free "inactivas".** La regla publicada es CPU, red y memoria por debajo de ~20%
  durante 7 días. Un asistente personal pasa casi todo el día esperando mensajes, así que **sí puede caer en esa
  regla**. Oracle avisa por correo antes. Si te pasa, tienes 2 opciones: convertir la cuenta a "Pay As You Go" (los
  recursos Always Free siguen gratis, pero cualquier cosa fuera del límite se cobra) o volver a crear la VM. Revisa la
  política vigente de Oracle antes de decidir.
