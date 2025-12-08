#!/bin/bash

#######################################
# Script de Instalação Docker Swarm
# Sistema: Ubuntu 24.04 LTS
# Componentes: Docker, Swarm, Traefik, Portainer
#######################################

set -e  # Para em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Função de log
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERRO]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[PASSO]${NC} $1"
}

# Banner
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════╗
║   INSTALAÇÃO DOCKER SWARM COMPLETA        ║
║   Ubuntu 24.04 LTS + Traefik + Portainer  ║
╚═══════════════════════════════════════════╝
EOF
echo -e "${NC}"

#######################################
# 1. VERIFICAÇÕES INICIAIS
#######################################
log_step "1/10 - Verificando requisitos do sistema"

# Verificar se é root
if [ "$EUID" -ne 0 ]; then 
    log_error "Execute como root: sudo bash setup-docker-swarm.sh"
    exit 1
fi

# Verificar versão do Ubuntu
if ! grep -q "24.04" /etc/os-release; then
    log_warning "Este script foi testado no Ubuntu 24.04 LTS"
    read -p "Deseja continuar mesmo assim? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        exit 1
    fi
fi

# Coletar informações
read -p "Digite o domínio principal (ex: menteestrategica.com.br): " DOMAIN
read -p "Digite seu email para Let's Encrypt: " EMAIL
read -p "Digite o hostname do servidor (ex: manager1): " HOSTNAME

log_info "Configurações:"
log_info "  Domínio: $DOMAIN"
log_info "  Email: $EMAIL"
log_info "  Hostname: $HOSTNAME"
echo

#######################################
# 2. ATUALIZAÇÃO DO SISTEMA
#######################################
log_step "2/10 - Atualizando sistema operacional"
apt-get update
apt-get upgrade -y
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    ufw \
    net-tools \
    htop \
    vim \
    git \
    wget

#######################################
# 3. CONFIGURAR HOSTNAME
#######################################
log_step "3/10 - Configurando hostname"
hostnamectl set-hostname "$HOSTNAME"
echo "127.0.0.1 localhost" > /etc/hosts
echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
log_info "Hostname configurado: $(hostname)"

#######################################
# 4. INSTALAR DOCKER (ÚLTIMA VERSÃO)
#######################################
log_step "4/10 - Instalando Docker (última versão)"

# Remover versões antigas
apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Adicionar repositório oficial Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Habilitar e iniciar Docker
systemctl enable docker
systemctl start docker

DOCKER_VERSION=$(docker --version)
log_info "Docker instalado: $DOCKER_VERSION"

#######################################
# 5. CONFIGURAR FIREWALL
#######################################
log_step "5/10 - Configurando firewall UFW"

# Resetar firewall
ufw --force reset

# Portas básicas
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Portas Docker Swarm
ufw allow 2377/tcp comment 'Docker Swarm Management'
ufw allow 7946/tcp comment 'Docker Swarm Node Communication'
ufw allow 7946/udp comment 'Docker Swarm Node Communication'
ufw allow 4789/udp comment 'Docker Overlay Network'

# Ativar firewall
ufw --force enable
ufw status numbered

log_info "Firewall configurado com sucesso"

#######################################
# 6. INICIALIZAR DOCKER SWARM
#######################################
log_step "6/10 - Inicializando Docker Swarm"

# Pegar IP principal do servidor
SERVER_IP=$(hostname -I | awk '{print $1}')
log_info "IP do servidor: $SERVER_IP"

# Inicializar Swarm
docker swarm init --advertise-addr "$SERVER_IP" 2>/dev/null || log_warning "Swarm já inicializado"

# Criar rede overlay
docker network create \
    --driver=overlay \
    --attachable \
    network_public 2>/dev/null || log_warning "Rede network_public já existe"

log_info "Docker Swarm inicializado"
docker node ls

#######################################
# 7. CRIAR VOLUMES PERSISTENTES
#######################################
log_step "7/10 - Criando volumes persistentes"

docker volume create volume_swarm_certificates
docker volume create volume_swarm_shared
docker volume create portainer_data

log_info "Volumes criados:"
docker volume ls | grep -E "volume_swarm|portainer_data"

#######################################
# 8. DEPLOY TRAEFIK
#######################################
log_step "8/10 - Fazendo deploy do Traefik"

cat > /root/traefik.yaml <<EOF
version: "3.8"

services:
  traefik:
    image: traefik:v3.2
    command:
      # Dashboard
      - "--api.dashboard=true"
      - "--api.insecure=false"
      
      # Docker Swarm Provider (v3 syntax)
      - "--providers.swarm.endpoint=unix:///var/run/docker.sock"
      - "--providers.swarm.exposedbydefault=false"
      - "--providers.swarm.network=network_public"
      
      # Entrypoints
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      - "--entrypoints.web.http.redirections.entrypoint.permanent=true"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.websecure.http.tls.certResolver=letsencryptresolver"
      
      # Let's Encrypt
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencryptresolver.acme.email=wambhz@gmail.com"
      - "--certificatesresolvers.letsencryptresolver.acme.storage=/etc/traefik/letsencrypt/acme.json"
      
      # Logs
      - "--log.level=INFO"
      - "--accesslog=true"
      
    ports:
      - target: 80
        published: 80
        mode: host
      - target: 443
        published: 443
        mode: host
        
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - volume_swarm_certificates:/etc/traefik/letsencrypt
      
    networks:
      - network_public
      
    deploy:
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        
        # Dashboard
        - "traefik.http.routers.dashboard.rule=Host(`traefik.menteestrategica.com.br`)"
        - "traefik.http.routers.dashboard.entrypoints=websecure"
        - "traefik.http.routers.dashboard.service=api@internal"
        - "traefik.http.routers.dashboard.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.dashboard.middlewares=auth"
        
        # Autenticação básica (user: admin, pass: admin)
        - "traefik.http.middlewares.auth.basicauth.users=admin:$$apr1$$8EVjn/nj$$GiLUZqcbueTFeD23SuB6x0"

volumes:
  volume_swarm_certificates:
    external: true

networks:
  network_public:
    external: true
EOF

docker stack deploy --prune --resolve-image always -c /root/traefik.yaml traefik

log_info "Traefik deployado com sucesso"
log_warning "Dashboard Traefik: https://traefik.$DOMAIN (user: admin | pass: admin)"

#######################################
# 9. DEPLOY PORTAINER
#######################################
log_step "9/10 - Fazendo deploy do Portainer"

cat > /root/portainer.yaml <<EOF
version: "3.8"

services:
  agent:
    image: portainer/agent:2.21.4
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - network_public
    deploy:
      mode: global
      placement:
        constraints:
          - node.platform.os == linux

  portainer:
    image: portainer/portainer-ce:2.21.4
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer_data:/data
    networks:
      - network_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.docker.network=network_public"
        - "traefik.http.routers.portainer.rule=Host(\`painel.$DOMAIN\`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.portainer.service=portainer"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"
        - "traefik.http.services.portainer.loadbalancer.server.scheme=http"

volumes:
  portainer_data:
    external: true

networks:
  network_public:
    external: true
EOF

# Aguardar Traefik subir
log_info "Aguardando Traefik inicializar (30s)..."
sleep 30

docker stack deploy --prune --resolve-image always -c /root/portainer.yaml portainer

log_info "Portainer deployado com sucesso"

#######################################
# 10. VERIFICAÇÕES FINAIS
#######################################
log_step "10/10 - Verificações finais"

log_info "Aguardando serviços subirem (45s)..."
sleep 45

echo
log_info "═══════════════════════════════════════"
log_info "STATUS DOS SERVIÇOS:"
docker service ls

echo
log_info "═══════════════════════════════════════"
log_info "INSTALAÇÃO CONCLUÍDA COM SUCESSO!"
echo
log_info "📋 INFORMAÇÕES DE ACESSO:"
echo
log_info "  🌐 Portainer:  https://painel.$DOMAIN"
log_info "  🔧 Traefik:    https://traefik.$DOMAIN"
log_info "     └─ User: admin | Pass: admin"
echo
log_info "⚠️  IMPORTANTE:"
log_info "  1. Configure os DNS antes de acessar:"
log_info "     - painel.$DOMAIN → $SERVER_IP"
log_info "     - traefik.$DOMAIN → $SERVER_IP"
echo
log_info "  2. Altere a senha do Traefik dashboard!"
log_info "     Execute: htpasswd -nb admin sua_nova_senha"
echo
log_info "  3. No primeiro acesso ao Portainer, crie o usuário admin"
echo
log_info "═══════════════════════════════════════"

# Salvar informações
cat > /root/INFO_INSTALACAO.txt <<EOF
═══════════════════════════════════════
INFORMAÇÕES DA INSTALAÇÃO
Data: $(date)
═══════════════════════════════════════

SERVIDOR:
- IP: $SERVER_IP
- Hostname: $HOSTNAME
- Domínio: $DOMAIN

ACESSOS:
- Portainer: https://painel.$DOMAIN
- Traefik Dashboard: https://traefik.$DOMAIN
  User: admin
  Pass: admin (ALTERE IMEDIATAMENTE!)

ARQUIVOS DE CONFIGURAÇÃO:
- /root/traefik.yaml
- /root/portainer.yaml

COMANDOS ÚTEIS:
- Ver serviços: docker service ls
- Ver logs Traefik: docker service logs traefik_traefik -f
- Ver logs Portainer: docker service logs portainer_portainer -f
- Reiniciar stack: docker stack deploy -c traefik.yaml traefik

PRÓXIMOS PASSOS:
1. Configure DNS apontando para $SERVER_IP
2. Acesse Portainer e crie usuário admin
3. Altere senha do Traefik dashboard
4. Configure backup dos volumes

═══════════════════════════════════════
EOF

log_info "Informações salvas em: /root/INFO_INSTALACAO.txt"
echo
