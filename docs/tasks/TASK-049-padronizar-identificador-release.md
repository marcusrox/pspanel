# TASK-049 - Padronizar identificador de release

## Contexto

O PS Panel mantém o identificador da versão implantada em
`src/config/release.js`. Atualmente o módulo exporta uma propriedade `label`
que já contém tanto o texto de apresentação quanto os dados da versão:

```js
module.exports = {
    label: 'Release 22/07/2026 11:59 - 035'
};
```

Esse valor é disponibilizado globalmente às views por `app.js`, apresentado no
rodapé por `views/partials/app-footer.ejs` e reutilizado na página de ambiente
por `src/services/runtimeEnvironmentService.js`.

O formato atual mistura apresentação (`Release`) com identificação técnica e
inclui hora. Isso dificulta usar o mesmo identificador como nome de tag Git e
como versão informada ao script `deploy/windows/Update-PSPanel.ps1`.

## Objetivo

Adotar um identificador canônico no formato:

```text
vAAAA.MM.DD-NNN
```

Exemplo de identificador armazenado:

```text
v2026.07.22-034
```

No rodapé, o prefixo de apresentação deve ser acrescentado pela view, gerando:

```text
Release v2026.07.22-034
```

## Importante

Esta task deve ser apenas preparada neste momento. Não implementar
automaticamente sem nova solicitação ou confirmação do usuário.

O sufixo `034` acima é apenas um exemplo de formato. A implementação não deve
reduzir nem reutilizar o sequencial vigente. Como o valor atual termina em
`035`, se nenhuma outra release for criada antes desta implementação, o novo
valor deverá terminar em `036`.

## Impactos identificados

| Componente | Uso atual | Alteração esperada |
| --- | --- | --- |
| `src/config/release.js` | Exporta `label` com texto completo, data, hora e sequencial. | Exportar o identificador técnico sem o prefixo visual e sem hora. |
| `app.js` | Carrega o módulo e o disponibiliza em `res.locals.release`. | Nenhuma mudança funcional esperada; preservar esse contrato global. |
| `views/partials/app-footer.ejs` | Exibe `release.label` diretamente. | Montar `Release ` mais o identificador técnico, mantendo saída escapada e fallback. |
| `src/services/runtimeEnvironmentService.js` | Usa `release.label` no resumo e nos detalhes do ambiente. | Consumir o novo campo; como a linha já se chama `Release`, exibir somente o identificador para não duplicar o prefixo. |
| `AGENTS.md` | Instrui futuras implementações a gravarem o formato antigo. | Atualizar a regra para que as próximas tasks mantenham o novo formato. |
| `deploy/windows/Update-PSPanel.ps1` | Aceita uma tag ou commit no parâmetro `-Version`. | Não exige mudança funcional; o novo identificador já é compatível com uma tag Git. |
| Tasks históricas | Algumas documentam releases no padrão anterior. | Permanecer inalteradas, pois representam o estado e as decisões de cada implementação passada. |

Não há impacto esperado no banco SQLite, autenticação, sessão, rotas, worker,
scripts PowerShell ou dependências NPM.

## Decisões de implementação

### Identificador canônico

O valor persistido no código deve obedecer a:

```regex
^v\d{4}\.\d{2}\.\d{2}-\d{3}$
```

Significado:

- `v`: prefixo técnico de versão;
- `AAAA.MM.DD`: data local em que a release foi concluída;
- `NNN`: sequencial global de três dígitos, incrementado em relação à última
  release existente.

A hora deixa de fazer parte do identificador. Múltiplas releases no mesmo dia
continuam distintas pelo sequencial.

### Contrato de `release.js`

Separar explicitamente o valor técnico do texto de apresentação. Estrutura
sugerida:

```js
module.exports = {
    version: 'v2026.07.22-036'
};
```

Não manter o nome `label` apenas por compatibilidade interna: o inventário
atual mostra somente dois consumidores e ambos devem ser atualizados na mesma
mudança. O nome `version` evita que código futuro pressuponha que o valor já
contém a palavra `Release`.

### Apresentação no rodapé

`views/partials/app-footer.ejs` deve ser responsável pelo texto visual:

```text
Release <identificador>
```

Continuar usando `<%= ... %>` para saída escapada. Se o módulo ou o campo não
estiver disponível, mostrar uma mensagem segura como `Release não informada`,
sem quebrar a renderização das páginas.

### Página de ambiente

As entradas de `src/services/runtimeEnvironmentService.js` já possuem o rótulo
`Release`. Seus valores devem ser apenas `release.version`, por exemplo:

```text
Release: v2026.07.22-036
```

O fallback atual deve ser preservado ou ajustado para `Não informado`, sem
incluir novamente o prefixo `Release` no valor.

### Sequencial e atualização futura

Ao concluir esta task e qualquer task posterior:

1. ler o último sufixo numérico de `src/config/release.js`;
2. incrementar o sequencial em 1, sem reiniciá-lo quando a data mudar;
3. usar a data local da conclusão no formato `AAAA.MM.DD`;
4. gravar o resultado como `vAAAA.MM.DD-NNN`;
5. nunca derivar o sequencial pela contagem de commits, horário ou versão do
   `package.json`.

A instrução correspondente em `AGENTS.md` deve ser atualizada na mesma
implementação para impedir que uma task futura restaure o padrão antigo.

## Relação com Git e deploy

O novo identificador foi escolhido para também ser válido como nome de tag Git.
Entretanto, `src/config/release.js` não deve consultar o Git em tempo de
execução, pois a aplicação precisa funcionar em instalações sem o executável no
`PATH` e sem depender dos metadados do repositório durante o startup.

A criação e o push da tag continuam sendo uma etapa explícita do processo de
release. Esta task não deve criar tags automaticamente. Quando houver uma tag,
seu nome deve ser igual ao valor de `release.version`, permitindo um deploy como:

```powershell
.\deploy\windows\Update-PSPanel.ps1 -Version 'v2026.07.22-036'
```

## Alterações propostas

1. Alterar `src/config/release.js` para exportar `version` no novo formato.
2. Atualizar `views/partials/app-footer.ejs` para acrescentar o prefixo visual
   `Release ` e usar o novo campo.
3. Atualizar os dois usos em `src/services/runtimeEnvironmentService.js` para
   ler `release.version`.
4. Preservar em `app.js` a disponibilização do objeto por
   `res.locals.release`.
5. Atualizar em `AGENTS.md` a regra de controle de release, substituindo o
   formato legado por `vAAAA.MM.DD-NNN` e removendo a exigência de hora.
6. Se houver documentação operacional nova que exemplifique o identificador,
   usar somente o padrão novo.

## Arquivos prováveis

```text
src/config/release.js
views/partials/app-footer.ejs
src/services/runtimeEnvironmentService.js
AGENTS.md
```

`app.js` deve ser validado como consumidor, mas não precisa ser alterado se o
objeto continuar disponível em `res.locals.release`.

## Compatibilidade e riscos

- A troca de `label` por `version` é uma quebra do contrato interno do módulo;
  todos os consumidores devem ser atualizados no mesmo commit.
- Se o rodapé continuar exibindo o campo diretamente, ficará ausente a palavra
  `Release`; por isso a view faz parte obrigatória da mudança.
- Se a página de ambiente acrescentar o prefixo ao valor, poderá exibir
  `Release: Release v...`; nessa página o valor deve permanecer somente técnico.
- Se `AGENTS.md` não for atualizado, a próxima task poderá reintroduzir o
  formato antigo.
- O valor gravado no código não comprova, sozinho, que existe uma tag Git com o
  mesmo nome. Essa consistência pertence ao processo de publicação.
- Cache de módulos CommonJS significa que a mudança só aparecerá após reiniciar
  o serviço Node.js, comportamento já esperado em um deploy.

## Fora de escopo

- Criar ou enviar tags Git automaticamente.
- Derivar a release por `git describe`, hash de commit ou variável de ambiente.
- Alterar `package.json` ou sincronizar sua propriedade `version`.
- Criar endpoint novo de versão ou health check.
- Alterar o fluxo do script `Update-PSPanel.ps1`.
- Reescrever o histórico das tasks antigas.
- Alterar banco de dados, dependências ou `package-lock.json`.

## Critérios de aceite

- `src/config/release.js` exporta o campo `version` no formato
  `vAAAA.MM.DD-NNN`.
- O sequencial é incrementado em relação à release vigente e nunca regressa ao
  número usado apenas como exemplo nesta task.
- O rodapé mostra exatamente `Release vAAAA.MM.DD-NNN`.
- O rodapé mantém fallback legível quando `release.version` estiver ausente.
- A saída dinâmica do rodapé continua escapada por EJS.
- A página de ambiente mostra o rótulo `Release` com o valor
  `vAAAA.MM.DD-NNN`, sem duplicar a palavra `Release`.
- Todos os usos ativos de `release.label` são eliminados ou migrados.
- `app.js` continua disponibilizando o objeto de release para as views.
- `AGENTS.md` passa a orientar futuras implementações a usar o novo formato.
- O identificador resultante pode ser informado diretamente como tag ao script
  de atualização, sem exigir alteração no script.
- Nenhuma dependência, dado SQLite ou configuração sensível é alterada.

## Testes sugeridos

1. Executar `node --check src/config/release.js`.
2. Executar `node --check src/services/runtimeEnvironmentService.js`.
3. Executar `node --check app.js`, mesmo que o arquivo não precise ser alterado,
   para validar o consumidor global.
4. Usar `rg "release\\.label|Release [0-9]{2}/[0-9]{2}/"` nos arquivos ativos e
   confirmar que o contrato e o formato antigos não permanecem no código de
   execução.
5. Iniciar uma instância temporária na porta `3100` ou na próxima porta livre,
   com `PORT` definido explicitamente.
6. Validar uma página autenticada que inclua o rodapé e confirmar visualmente o
   texto `Release vAAAA.MM.DD-NNN`.
7. Validar a página de ambiente e confirmar que o resumo e os detalhes exibem
   somente uma ocorrência da palavra `Release` por campo.
8. Simular em teste o campo ausente e confirmar que o fallback não quebra a
   renderização.
9. Encerrar somente o processo temporário iniciado para a validação; nunca usar
   nem interromper a porta `3000`.

Não executar `npm test`, pois o projeto ainda não possui testes reais
configurados.

---

## Assinatura da LLM

- Data: 22/07/2026 14:59
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao
