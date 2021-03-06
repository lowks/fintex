defmodule FinTex.Segment.HKCCS do
  @moduledoc false

  alias FinTex.Command.AbstractCommand
  alias FinTex.Model.Account
  alias FinTex.Model.Dialog
  alias FinTex.Model.Payment
  alias FinTex.Parser.Lexer

  @supported_sepa_descriptor_urns [
    "urn:iso:std:iso:20022:tech:xsd:pain.001.002.03.xsd",
    "urn:iso:std:iso:20022:tech:xsd:pain.001.003.03.xsd"
  ]

  import XmlBuilder
  use AbstractCommand
  use Timex

  defstruct [:payment]

  def create(
    payment = %__MODULE__{
      payment: %Payment{
        sender_account: %Account{
          iban:  sender_iban,
          bic:   sender_bic
        }
      }
    },
    %Dialog{:bpd => bpd}) do

    ktv = [sender_iban, sender_bic]


    sepa_descriptor_urn = bpd
    |> Dict.get(control_structure_to_bpd("HKSPA"))
    |> Enum.at(0)
    |> Enum.at(-1)
    |> Enum.at(-1)
    |> Enum.find(fn urn -> @supported_sepa_descriptor_urns |> Enum.any?(fn s -> String.contains?(s, urn) end) end)

    sepa_descriptor = ~r/\.xsd$/
    |> Regex.replace(sepa_descriptor_urn, "")

    sepa_pain_message = sepa_pain_message(sepa_descriptor, payment) |> Lexer.encode_binary

    [
      ["HKCCS", "?", 1],
      ktv,
      sepa_descriptor,
      sepa_pain_message
    ]
  end


  defp sepa_pain_message(schema, payment) when is_binary(schema) do
    %__MODULE__{
      payment: %Payment{
        sender_account: %Account{
          iban:  sender_iban,
          bic:   sender_bic,
          owner: sender_owner
        },
        receiver_account: %Account{
          iban:  receiver_iban,
          bic:   receiver_bic,
          owner: receiver_owner
        },
        amount: amount,
        currency: currency,
        purpose: purpose
      }
    } = payment

    amount = amount |> to_string

    doc(
      :Document,
      %{
        "xmlns":              schema,
        "xsi:schemaLocation": schema |> schema_to_location,
        "xmlns:xsi":          "http://www.w3.org/2001/XMLSchema-instance"
      },
      [
        CstmrCdtTrfInitn: [
          GrpHdr: [
            MsgId: "M" <> DateFormat.format!(Date.now, "%Y%m%d%H%M%S", :strftime),
            CreDtTm: DateFormat.format!(Date.now, "{ISOz}"),
            NbOfTxs: 1,
            CtrlSum: amount,
            InitgPty: [
              Nm: sender_owner || ""
            ]
          ],
          PmtInf: [
            PmtInfId: "P" <> DateFormat.format!(Date.now, "%Y%m%d%H%M%S", :strftime),
            PmtMtd: "TRF",
            NbOfTxs: 1,
            CtrlSum: amount,
            PmtTpInf: [
              SvcLvl: [
                Cd: "SEPA"
              ]
            ],
            ReqdExctnDt: "1999-01-01",
            Dbtr: [
              Nm: sender_owner || ""
            ],
            DbtrAcct: [
              Id: [
                IBAN: sender_iban || ""
              ],
              Ccy: currency
            ],
            DbtrAgt: [
              FinInstnId: [
                BIC: sender_bic || ""
              ]
            ],
            ChrgBr: "SLEV",
            CdtTrfTxInf: [
              PmtId: [
                EndToEndId: "NOTPROVIDED"
              ],
              Amt: [
                {:InstdAmt, %{Ccy: currency}, amount}
              ],
              CdtrAgt: [
                FinInstnId: [
                  BIC: receiver_bic || ""
                ]
              ],
              Cdtr: [
                Nm: receiver_owner || ""
              ],
              CdtrAcct: [
                Id: [
                  IBAN: receiver_iban || ""
                ]
              ],
              RmtInf: [
                Ustrd: purpose || ""
              ]
            ]
          ]
        ]
      ]
    )
    |> String.replace("\n", "")
    |> String.replace("\t", "")
  end


  defp schema_to_location(schema) when is_binary(schema) do
    ~r/^(.*:)(pain.*)$/
    |> Regex.replace(schema, "\\1\\2 \\2.xsd", global: false)
  end
end
