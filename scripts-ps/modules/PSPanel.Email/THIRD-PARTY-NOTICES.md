# Componentes de terceiros do PSPanel.Email

As DLLs deste diretorio foram obtidas de pacotes oficiais do NuGet e sao distribuidas sob a licenca MIT.

| Arquivo | Pacote e versao | Origem | SHA-256 |
|---|---|---|---|
| `lib/MailKit.dll` | MailKit 4.17.0 (`net10.0`) | `https://api.nuget.org/v3-flatcontainer/mailkit/4.17.0/mailkit.4.17.0.nupkg` | `2CB259E17621ED8C608B530DED7BC9D6F42A3D1D23C63C03B16C5C4A422C815F` |
| `lib/MimeKit.dll` | MimeKit 4.17.0 (`net10.0`) | `https://api.nuget.org/v3-flatcontainer/mimekit/4.17.0/mimekit.4.17.0.nupkg` | `CD0304ECD585D241B7928E69372DEC02D820041AF5004316821B17F31DDB2E0A` |
| `lib/BouncyCastle.Cryptography.dll` | BouncyCastle.Cryptography 2.6.2 (`net6.0`) | `https://api.nuget.org/v3-flatcontainer/bouncycastle.cryptography/2.6.2/bouncycastle.cryptography.2.6.2.nupkg` | `E5EEAF6D263C493619982FD3638E6135077311D08C961E1FE128F9107D29EBC6` |

MailKit e MimeKit: Copyright .NET Foundation and Contributors.

BouncyCastle.Cryptography: Copyright Legion of the Bouncy Castle Inc. 2000-2025.

## Licenca MIT

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Atualizacao

Ao atualizar qualquer pacote, baixar a nova versao da origem oficial, selecionar o assembly compativel com o runtime do PowerShell usado pelo PS Panel, revisar dependencias e licenca, substituir a DLL e recalcular o SHA-256.
