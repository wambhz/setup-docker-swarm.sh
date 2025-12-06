📝 Como Usar o Script
1️⃣ Após instalar o Ubuntu 24.04 na VPS:
bash# Fazer login como root
ssh root@seu_ip

# Baixar o script
wget https://raw.githubusercontent.com/seu-repo/setup-docker-swarm.sh
# OU copie o conteúdo do artifact acima

# Tornar executável
chmod +x setup-docker-swarm.sh

# Executar
sudo bash setup-docker-swarm.sh
```

### 2️⃣ O script vai pedir:
- **Domínio**: `menteestrategica.com.br`
- **Email**: Seu email para certificados SSL
- **Hostname**: `manager1` (ou o nome que preferir)

### 3️⃣ O que o script faz automaticamente:

✅ Atualiza o sistema  
✅ Instala Docker (última versão)  
✅ Configura firewall UFW  
✅ Inicializa Docker Swarm  
✅ Cria redes e volumes  
✅ Deploy Traefik v3.2 com SSL automático  
✅ Deploy Portainer CE 2.21.4  
✅ Configura Traefik Dashboard  

---

## 🌐 Configuração DNS no Cloudflare

Após rodar o script, configure estes registros DNS:
```
Tipo    Nome       Valor           Proxy   TTL
────────────────────────────────────────────────
A       @          SEU_IP_VPS      ❌      Auto
A       painel     SEU_IP_VPS      ❌      Auto
A       traefik    SEU_IP_VPS      ❌      Auto
A       server     SEU_IP_VPS      ❌      Auto
CNAME   www        @               ✅      Auto
⚠️ IMPORTANTE: Desative o proxy (nuvem laranja) nos registros que usam Traefik!

🔐 Primeiro Acesso
Portainer

Acesse: https://painel.menteestrategica.com.br
Crie usuário admin na primeira vez
Conecte ao ambiente local

Traefik Dashboard

Acesse: https://traefik.menteestrategica.com.br
User: admin | Pass: admin
ALTERE A SENHA IMEDIATAMENTE!

Para gerar nova senha:
bashapt-get install apache2-utils -y
htpasswd -nb admin sua_nova_senha
# Copie o resultado e atualize no traefik.yaml

🛠️ Comandos Úteis
bash# Ver todos os serviços
docker service ls

# Logs do Traefik
docker service logs traefik_traefik -f

# Logs do Portainer
docker service logs portainer_portainer -f

# Reiniciar uma stack
docker stack rm traefik
docker stack deploy -c /root/traefik.yaml traefik

# Verificar certificados SSL
docker exec $(docker ps -q -f name=traefik) ls -la /etc/traefik/letsencrypt/

📊 Especificações do Servidor
Para seu servidor (4 núcleos, 16GB RAM):
StackCPURAMStorageTraefik0.5128MB100MBPortainer0.5256MB500MBDisponível3 cores15.5GBMuito
Você tem recursos mais que suficientes! 🚀
