# Configuração do OBS (modo live)

O modo live entrega **uma fonte horizontal**. O 9:16 é feito com crop dentro do OBS. `TcpPublisher` (iOS + Android) faz broadcast do mesmo MPEG-TS para vários clientes na mesma porta. Mesmo assim, o caminho mais leve é uma fonte só com Source Mirror.

## Fonte horizontal

1. Add Source → **Media Source** (não "Browser", não "Stream").
2. Desmarcar "Local File".
3. **Input:** `tcp://IP_DO_CELULAR:9000`.
4. **Input Format:** `mpegts`.
5. ☑ Reiniciar reprodução quando ativa.
6. ☑ Usar decodificação por hardware quando disponível.
7. **Argumentos avançados de entrada:**
   ```
   fflags=nobuffer+discardcorrupt
   flags=low_delay
   probesize=32
   analyzeduration=0
   ```
8. Reconnect Delay: 1 s.

Sem essas flags, o OBS buferiza cerca de 1 s e o vídeo chega em rajadas. TCP plano não tem ARQ: perda na Wi-Fi vira stall. Requisitos: Wi-Fi 5 GHz, mesmo SSID e mesmo AP.

## Cena vertical 9:16

Usa Source Mirror da Media Source horizontal, sem segunda Media Source.

**Opção A — Filtro Crop/Pad:**
1. Cena nova com canvas 1080×1920.
2. Add → Source Mirror → Media Source horizontal.
3. Filters → + → **Crop/Pad**: Left 656, Right 656 (`(W - 9*H/16)/2` por lado, para 1920×1080).
4. Escalar até preencher 1080×1920.

Left ≠ Right desloca o centro do crop.

**Opção B — Transform:**
1. Cena com canvas 1080×1920.
2. Source Mirror da Media Source horizontal.
3. Transform → Edit Transform → Crop: Left 656, Right 656.
4. Position 0,0; Bounding Box 1080×1920 fit.

A resolução de saída por cena exige o plugin "Auto Resolution" ou uma exportação 1080×1920 separada.

## Câmera virtual (Windows/macOS)

O LiveGrid é fonte de OBS. A Virtual Camera embutida do OBS expõe a cena ativa como webcam: OBS → **Iniciar Câmera Virtual** → selecionar **OBS Virtual Camera** no Zoom/Teams/Meet. No macOS, o primeiro uso instala um plugin DAL e pede senha. Não há driver próprio.
