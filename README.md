# PS Panel 🚀

Um painel web moderno e intuitivo para execução e gerenciamento de scripts PowerShell, desenvolvido com Node.js e Express.

![PS Panel Screenshot](screenshot.png)

## 📋 Sobre o Projeto

O PS Panel é uma aplicação web que permite executar e gerenciar scripts PowerShell de forma centralizada através de uma interface amigável e moderna. Ideal para equipes de infraestrutura e DevOps que precisam executar scripts PowerShell de forma controlada e organizada.

### ✨ Principais Características

- 🎯 Interface web moderna e responsiva
- 📁 Gerenciamento centralizado de scripts PowerShell
- 🔄 Execução remota de scripts com parâmetros
- 📊 Visualização em tempo real da saída dos scripts
- 🔐 Interface segura e controlada
- 📱 Design responsivo para diferentes dispositivos
- 💬 Integração com WhatsApp para notificações (via Evolution API)

## 🛠️ Tecnologias Utilizadas

- **Backend:**
  - Node.js
  - Express.js
  - PowerShell (para execução dos scripts)

- **Frontend:**
  - HTML5
  - CSS3 (com variáveis CSS para temas)
  - HTMX (para interatividade)
  - Font Awesome (para ícones)

## 📦 Pré-requisitos

- Node.js (versão 14 ou superior)
- PowerShell 5.1 ou superior
- Acesso de administrador para execução de scripts PowerShell

## 🚀 Instalação

1. Clone o repositório:
```bash
git clone https://github.com/seu-usuario/pspanel.git
cd pspanel
```

2. Instale as dependências:
```bash
npm install
```

3. Configure as variáveis de ambiente:
```bash
cp .env.example .env
# Edite o arquivo .env com suas configurações
```

4. Inicie a aplicação:
```bash
npm start
```

Para desenvolvimento, você pode usar:
```bash
npm run dev
```

## 🔧 Configuração

### Variáveis de Ambiente

Crie um arquivo `.env` na raiz do projeto com as seguintes variáveis:

```env
PORT=3000
NODE_ENV=production
```

### Scripts PowerShell

- Coloque seus scripts PowerShell no diretório `scripts/`
- Apenas arquivos com extensão `.ps1` serão listados no painel
- Recomenda-se documentar os parâmetros no início de cada script

## 📚 Estrutura do Projeto

```
pspanel/
├── app.js              # Arquivo principal da aplicação
├── public/             # Arquivos estáticos
│   ├── styles.css      # Estilos da aplicação
│   └── logo.png        # Logo da aplicação
├── views/              # Templates HTML
│   └── index.html      # Página principal
├── scripts/            # Scripts PowerShell
│   ├── Deploy-IIS.ps1
│   ├── Backup-Fortigate.ps1
│   └── Test-Zap.ps1
└── package.json        # Dependências e scripts
```

## 🔒 Segurança

- Os scripts são executados em um ambiente controlado
- Apenas scripts localizados no diretório `scripts/` podem ser executados
- Validação de parâmetros antes da execução
- Execução isolada de cada script

## 🤝 Contribuindo

1. Faça um Fork do projeto
2. Crie uma branch para sua feature (`git checkout -b feature/AmazingFeature`)
3. Commit suas mudanças (`git commit -m 'Add some AmazingFeature'`)
4. Push para a branch (`git push origin feature/AmazingFeature`)
5. Abra um Pull Request

## 📝 Licença

Este projeto está sob a licença ISC. Veja o arquivo [LICENSE](LICENSE) para mais detalhes.

## ✨ Funcionalidades Principais

### Execução de Scripts
- Seleção de scripts através de interface dropdown
- Suporte a parâmetros customizados
- Visualização em tempo real da saída
- Histórico de execuções

### Notificações
- Integração com WhatsApp através da Evolution API
- Notificações de conclusão de scripts
- Status de execução em tempo real

### Interface
- Design moderno e intuitivo
- Tema escuro por padrão
- Ícones intuitivos
- Responsividade para diferentes dispositivos

## 📞 Suporte

Para suporte, envie um email para [seu-email@exemplo.com](mailto:seu-email@exemplo.com) ou abra uma issue no GitHub.

---

Desenvolvido com ❤️ pela equipe de Infraestrutura
