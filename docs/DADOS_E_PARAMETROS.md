# Dados, categorias e parâmetros

[Início](../README.md) · [Uso](INSTALACAO_E_USO.md)

## `metadata.json`

Criado automaticamente no pacote local. Exemplo fictício, sem credenciais:

```json
{
  "schema_version": 1,
  "output_name": "Torneira Exemplo.rfa",
  "generator": {"name": "FamilyBridge", "version": "0.9.2", "author": "Yruam Käffer de Faria"},
  "product": {
    "manufacturer": "Fabricante Exemplo",
    "code": "EX-001",
    "name": "Torneira Exemplo",
    "collection": "Linha A",
    "finish": "Cromado",
    "description": "Descrição do produto",
    "website": "https://example.com/produto",
    "category": "Plumbing Fixtures"
  },
  "geometry": {
    "file": "model.step",
    "format": "STEP ISO 10303",
    "unit": "mm",
    "dimensions_mm": {"x": 100.0, "y": 80.0, "z": 150.0}
  },
  "exported_at_utc": "2026-10-22T12:00:00Z"
}
```

O campo `geometry.dimensions_mm` vem dos limites do **SKP** em milímetros. Use o STEP e a família final para validar dimensões do sólido. `output_name` usa o nome do SKP salvo ou, se não houver, código e nome normalizados. Código e nome são obrigatórios; os demais campos de produto podem ficar vazios. O site é copiado como digitado, sem reparo automático da URL.

## Mapeamento do produto

| Campo do painel / JSON | Parâmetro customizado na família | Parâmetro nativo, se editável |
| --- | --- | --- |
| Fabricante / `manufacturer` | `FB_Fabricante` | Manufacturer |
| Código / `code` | `FB_Codigo` | Model |
| Nome / `name` | `FB_Produto` | — |
| Linha / `collection` | `FB_Linha` | — |
| Acabamento / `finish` | `FB_Acabamento` | — |
| Descrição / `description` | `FB_Descricao` | Description |
| Site / `website` | `FB_Site` | URL |
| Categoria / `category` | Categoria da família | — |

Os parâmetros `FB_*` são parâmetros **de família, de texto, por tipo** criados pelo worker. Os nativos são definidos apenas quando o template disponibiliza parâmetros editáveis. Os nomes visíveis dos nativos dependem do idioma do Revit.

| Opção no painel | Identificador JSON | Categoria Revit |
| --- | --- | --- |
| Modelos genéricos | `Generic Models` | `OST_GenericModel` |
| Peças hidráulicas | `Plumbing Fixtures` | `OST_PlumbingFixtures` |
| Equipamentos mecânicos | `Mechanical Equipment` | `OST_MechanicalEquipment` |
| Mobiliário | `Furniture` | `OST_Furniture` |

Escolher uma categoria não cria conectores, regras MEP ou famílias hospedadas.

## `colors.json`

Artefato produzido pelo Fusion e consumido pelo Revit:

```json
{
  "schema_version": 1,
  "bodies": [
    {"dimensions_mm": [80.0, 100.0, 150.0], "min_mm": [0.0, 0.0, 0.0], "max_mm": [100.0, 80.0, 150.0], "volume_mm3": 123456.0, "rgb": [220, 220, 220]}
  ]
}
```

Cada entrada corresponde a um corpo sólido; os valores RGB inteiros vão de 0 a 255. Os nomes `FamilyBridge RGB R-G-B` identificam materiais de cor usados nos elementos. O manifesto não guarda textura, brilho, transparência ou cor por face. Os valores acima são ilustrativos e não descrevem um produto real.

## `bodies.fbdat`

Arquivo binário produzido pelo Fusion, contendo um SAT separado por corpo na ordem das entradas de `colors.json`. Cabeçalho ASCII `FBB1`, contagem UInt32 little endian e, para cada SAT, comprimento UInt32 little endian mais bytes. O Revit não abre o arquivo diretamente: o worker valida e extrai cada SAT para importar individualmente. `model.sat` completo é mantido apenas para diagnóstico. Para repetir só o Revit na v0.9.2, são obrigatórios `bodies.fbdat` e `steps.fbdat` de um pacote v0.9.2+ com `isolation_coordinates: assembly_mm`.

## `steps.fbdat`

Arquivo binário FBS1: assinatura ASCII `FBS1`, contagem UInt32 little endian e, por corpo, comprimento UInt32 little endian e bytes de um STEP ISO-10303-21. A ordem acompanha `bodies.fbdat` e `colors.json`. O worker extrai cada STEP e tenta importá-lo quando o SAT correspondente não gera exatamente um sólido. O limite por arquivo é 100 MB.

## Representação mista no RFA

Cada corpo é tentado como sólido pelas rotas SAT, STEP e `ShapeImporter`. Se nenhuma devolver exatamente um sólido com volume positivo, somente esse corpo pode ser salvo como malha `DirectShape` com material RGB. O worker confere caixa (desvio < 5 mm) e volume da malha orientada (diferença < 2%) frente ao manifesto do Fusion e registra os índices que usaram malha. Uma malha não equivale a um sólido paramétrico.
