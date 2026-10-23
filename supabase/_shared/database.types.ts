export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.18"
  }
  public: {
    Tables: {
      agent_commission: {
        Row: {
          agent_id: string
          amount: number
          commission_amount: number
          commission_rate: number
          country_code: string
          created_at: string
          currency_code: string
          document_number: string
          fee_amount: number
          fiscal_year: number
          id: string
          is_settled: boolean
          period: number
          reference: string | null
          settled_at: string | null
          settled_by: string | null
          settlement_batch_id: string | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Insert: {
          agent_id: string
          amount: number
          commission_amount: number
          commission_rate: number
          country_code: string
          created_at?: string
          currency_code: string
          document_number: string
          fee_amount: number
          fiscal_year: number
          id?: string
          is_settled?: boolean
          period: number
          reference?: string | null
          settled_at?: string | null
          settled_by?: string | null
          settlement_batch_id?: string | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Update: {
          agent_id?: string
          amount?: number
          commission_amount?: number
          commission_rate?: number
          country_code?: string
          created_at?: string
          currency_code?: string
          document_number?: string
          fee_amount?: number
          fiscal_year?: number
          id?: string
          is_settled?: boolean
          period?: number
          reference?: string | null
          settled_at?: string | null
          settled_by?: string | null
          settlement_batch_id?: string | null
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
        }
        Relationships: [
          {
            foreignKeyName: "agent_commission_agent_id_fkey"
            columns: ["agent_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agent_commission_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "agent_commission_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_settlement_batch_fk"
            columns: ["settlement_batch_id"]
            isOneToOne: false
            referencedRelation: "agent_settlement_batch"
            referencedColumns: ["id"]
          },
        ]
      }
      agent_fee_splitting_config: {
        Row: {
          country_code: string
          created_at: string
          created_by: string
          currency_code: string
          fiscal_year: number
          id: string
          is_active: boolean
          period: number
          rate: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          country_code: string
          created_at?: string
          created_by?: string
          currency_code: string
          fiscal_year: number
          id?: string
          is_active?: boolean
          period: number
          rate: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          country_code?: string
          created_at?: string
          created_by?: string
          currency_code?: string
          fiscal_year?: number
          id?: string
          is_active?: boolean
          period?: number
          rate?: number
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "agent_fee_splitting_config_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      agent_settlement_batch: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          country_code: string
          created_at: string
          created_by: string
          currency_code: string
          document_number: string
          end_date: string
          error_message: string | null
          fiscal_year: number
          id: string
          paid_at: string | null
          period: number
          reference: string | null
          start_date: string
          status: Database["public"]["Enums"]["SettlementStatus"]
          total_agents: number
          total_amount: number
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          country_code: string
          created_at?: string
          created_by: string
          currency_code: string
          document_number: string
          end_date: string
          error_message?: string | null
          fiscal_year: number
          id?: string
          paid_at?: string | null
          period: number
          reference?: string | null
          start_date: string
          status?: Database["public"]["Enums"]["SettlementStatus"]
          total_agents: number
          total_amount: number
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          country_code?: string
          created_at?: string
          created_by?: string
          currency_code?: string
          document_number?: string
          end_date?: string
          error_message?: string | null
          fiscal_year?: number
          id?: string
          paid_at?: string | null
          period?: number
          reference?: string | null
          start_date?: string
          status?: Database["public"]["Enums"]["SettlementStatus"]
          total_agents?: number
          total_amount?: number
        }
        Relationships: [
          {
            foreignKeyName: "agent_settlement_batch_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "agent_settlement_batch_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      agent_settlement_item: {
        Row: {
          agent_id: string
          batch_id: string
          country_code: string
          currency_code: string
          error_message: string | null
          fiscal_year: number
          id: string
          paid_at: string | null
          period: number
          status: Database["public"]["Enums"]["SettlementStatus"]
          total_commission: number
          total_fees_generated: number
          total_withdrawal_volume: number
        }
        Insert: {
          agent_id: string
          batch_id: string
          country_code: string
          currency_code: string
          error_message?: string | null
          fiscal_year: number
          id?: string
          paid_at?: string | null
          period: number
          status?: Database["public"]["Enums"]["SettlementStatus"]
          total_commission: number
          total_fees_generated: number
          total_withdrawal_volume: number
        }
        Update: {
          agent_id?: string
          batch_id?: string
          country_code?: string
          currency_code?: string
          error_message?: string | null
          fiscal_year?: number
          id?: string
          paid_at?: string | null
          period?: number
          status?: Database["public"]["Enums"]["SettlementStatus"]
          total_commission?: number
          total_fees_generated?: number
          total_withdrawal_volume?: number
        }
        Relationships: [
          {
            foreignKeyName: "agent_settlement_item_agent_id_fkey"
            columns: ["agent_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agent_settlement_item_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "agent_settlement_batch"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "agent_settlement_item_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "agent_settlement_item_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      aml_config: {
        Row: {
          country_code: string
          created_at: string
          created_by: string
          currency_code: string
          fiscal_year: number
          id: string
          is_active: boolean
          period: number
          threshold_amount: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          country_code: string
          created_at?: string
          created_by?: string
          currency_code: string
          fiscal_year: number
          id?: string
          is_active?: boolean
          period: number
          threshold_amount: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          country_code?: string
          created_at?: string
          created_by?: string
          currency_code?: string
          fiscal_year?: number
          id?: string
          is_active?: boolean
          period?: number
          threshold_amount?: number
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "aml_config_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      asset_entry: {
        Row: {
          country_code: string
          created_at: string
          created_by: string
          credit: number
          currency_code: string
          debit: number
          document_number: string
          fiscal_year: number
          id: string
          period: number
          price: number
          reference: string | null
          total_value: number
          uom: Database["public"]["Enums"]["Uom"]
        }
        Insert: {
          country_code: string
          created_at?: string
          created_by: string
          credit: number
          currency_code: string
          debit: number
          document_number: string
          fiscal_year: number
          id?: string
          period: number
          price: number
          reference?: string | null
          total_value: number
          uom?: Database["public"]["Enums"]["Uom"]
        }
        Update: {
          country_code?: string
          created_at?: string
          created_by?: string
          credit?: number
          currency_code?: string
          debit?: number
          document_number?: string
          fiscal_year?: number
          id?: string
          period?: number
          price?: number
          reference?: string | null
          total_value?: number
          uom?: Database["public"]["Enums"]["Uom"]
        }
        Relationships: [
          {
            foreignKeyName: "asset_entry_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "asset_entry_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      asset_reserve: {
        Row: {
          acquisition_date: string
          asset_entry_id: string
          bar_serial_number: string
          cost_basis: number | null
          country_code: string
          created_at: string
          created_by: string | null
          currency_code: string
          custodian_name: string | null
          document_number: string
          fiscal_year: number
          id: string
          is_active: boolean
          period: number
          price: number | null
          purity: number | null
          quantity: number
          reference: string | null
          supplier_name: string | null
          total_value: number | null
          type: Database["public"]["Enums"]["AssetType"]
          uom: Database["public"]["Enums"]["Uom"]
          vault_reference: string | null
        }
        Insert: {
          acquisition_date: string
          asset_entry_id: string
          bar_serial_number: string
          cost_basis?: number | null
          country_code: string
          created_at?: string
          created_by?: string | null
          currency_code: string
          custodian_name?: string | null
          document_number: string
          fiscal_year: number
          id?: string
          is_active?: boolean
          period: number
          price?: number | null
          purity?: number | null
          quantity: number
          reference?: string | null
          supplier_name?: string | null
          total_value?: number | null
          type: Database["public"]["Enums"]["AssetType"]
          uom?: Database["public"]["Enums"]["Uom"]
          vault_reference?: string | null
        }
        Update: {
          acquisition_date?: string
          asset_entry_id?: string
          bar_serial_number?: string
          cost_basis?: number | null
          country_code?: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          custodian_name?: string | null
          document_number?: string
          fiscal_year?: number
          id?: string
          is_active?: boolean
          period?: number
          price?: number | null
          purity?: number | null
          quantity?: number
          reference?: string | null
          supplier_name?: string | null
          total_value?: number | null
          type?: Database["public"]["Enums"]["AssetType"]
          uom?: Database["public"]["Enums"]["Uom"]
          vault_reference?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "asset_reserve_asset_entry_id_fkey"
            columns: ["asset_entry_id"]
            isOneToOne: false
            referencedRelation: "asset_entry"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "asset_reserve_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "asset_reserve_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      audit_log: {
        Row: {
          action_type: Database["public"]["Enums"]["AuditActionType"]
          country_code: string
          created_at: string
          document_number: string
          endpoint: string | null
          entity_id: string | null
          entity_type: string | null
          fiscal_year: number
          id: number
          ip_address: string | null
          metadata: Json | null
          method: string | null
          new_value: Json | null
          old_value: Json | null
          period: number
          request_id: string | null
          status_code: number | null
          user_id: string
        }
        Insert: {
          action_type: Database["public"]["Enums"]["AuditActionType"]
          country_code: string
          created_at?: string
          document_number: string
          endpoint?: string | null
          entity_id?: string | null
          entity_type?: string | null
          fiscal_year: number
          id?: number
          ip_address?: string | null
          metadata?: Json | null
          method?: string | null
          new_value?: Json | null
          old_value?: Json | null
          period: number
          request_id?: string | null
          status_code?: number | null
          user_id: string
        }
        Update: {
          action_type?: Database["public"]["Enums"]["AuditActionType"]
          country_code?: string
          created_at?: string
          document_number?: string
          endpoint?: string | null
          entity_id?: string | null
          entity_type?: string | null
          fiscal_year?: number
          id?: number
          ip_address?: string | null
          metadata?: Json | null
          method?: string | null
          new_value?: Json | null
          old_value?: Json | null
          period?: number
          request_id?: string | null
          status_code?: number | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "audit_log_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "audit_log_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      blockchain_transaction: {
        Row: {
          blockchain_code: string | null
          chain: string
          chain_status: string | null
          country_code: string
          created_at: string
          created_by: string | null
          currency_code: string
          description: string | null
          document_number: string | null
          explorer_url: string | null
          fee_amount: number
          fiscal_year: number
          gross_amount: number
          id: string
          net_amount: number
          period: number
          quantity: number
          receiver: string
          reference: string | null
          sender: string
          status: Database["public"]["Enums"]["BlockchainTxStatus"]
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          tx_hash: string
        }
        Insert: {
          blockchain_code?: string | null
          chain: string
          chain_status?: string | null
          country_code: string
          created_at?: string
          created_by?: string | null
          currency_code: string
          description?: string | null
          document_number?: string | null
          explorer_url?: string | null
          fee_amount: number
          fiscal_year: number
          gross_amount: number
          id?: string
          net_amount: number
          period: number
          quantity: number
          receiver: string
          reference?: string | null
          sender: string
          status: Database["public"]["Enums"]["BlockchainTxStatus"]
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          tx_hash: string
        }
        Update: {
          blockchain_code?: string | null
          chain?: string
          chain_status?: string | null
          country_code?: string
          created_at?: string
          created_by?: string | null
          currency_code?: string
          description?: string | null
          document_number?: string | null
          explorer_url?: string | null
          fee_amount?: number
          fiscal_year?: number
          gross_amount?: number
          id?: string
          net_amount?: number
          period?: number
          quantity?: number
          receiver?: string
          reference?: string | null
          sender?: string
          status?: Database["public"]["Enums"]["BlockchainTxStatus"]
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          tx_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "blockchain_transaction_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "blockchain_transaction_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_blockchain_code_fk"
            columns: ["blockchain_code"]
            isOneToOne: false
            referencedRelation: "supported_blockchain"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      collateral: {
        Row: {
          country_code: string
          created_at: string
          id: string
          loanId: string | null
          locked_tokens: number
          updated_at: string
          user_id: string
        }
        Insert: {
          country_code: string
          created_at?: string
          id?: string
          loanId?: string | null
          locked_tokens?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          country_code?: string
          created_at?: string
          id?: string
          loanId?: string | null
          locked_tokens?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "collateral_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      collateral_balance_snapshot: {
        Row: {
          closing_balance: number
          country_code: string
          created_at: string
          credit: number
          debit: number
          fiscal_year: number
          id: string
          opening_balance: number
          period: number
          updated_at: string
          user_id: string
        }
        Insert: {
          closing_balance: number
          country_code: string
          created_at?: string
          credit: number
          debit: number
          fiscal_year: number
          id?: string
          opening_balance: number
          period: number
          updated_at?: string
          user_id: string
        }
        Update: {
          closing_balance?: number
          country_code?: string
          created_at?: string
          credit?: number
          debit?: number
          fiscal_year?: number
          id?: string
          opening_balance?: number
          period?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_country_fiscal_period_fk"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_user_id_fk"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      collateral_entry: {
        Row: {
          country_code: string
          created_at: string
          credit: number
          debit: number
          document_number: string
          id: number
          loan_id: string
          reference: string | null
          reversal_of: string | null
          reversed_by: string | null
        }
        Insert: {
          country_code: string
          created_at?: string
          credit?: number
          debit?: number
          document_number: string
          id?: number
          loan_id: string
          reference?: string | null
          reversal_of?: string | null
          reversed_by?: string | null
        }
        Update: {
          country_code?: string
          created_at?: string
          credit?: number
          debit?: number
          document_number?: string
          id?: number
          loan_id?: string
          reference?: string | null
          reversal_of?: string | null
          reversed_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "collateral_entry_loan_id_fkey"
            columns: ["loan_id"]
            isOneToOne: false
            referencedRelation: "loan"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      country_currencies: {
        Row: {
          country_code: string
          created_at: string
          created_by: string
          currency_code: string
          id: string
          is_active: boolean
          is_reporting: boolean
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          country_code: string
          created_at?: string
          created_by?: string
          currency_code: string
          id?: string
          is_active?: boolean
          is_reporting?: boolean
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          country_code?: string
          created_at?: string
          created_by?: string
          currency_code?: string
          id?: string
          is_active?: boolean
          is_reporting?: boolean
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "country_currencies_country_code_fkey"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "country_currencies_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
        ]
      }
      credit_agent_account: {
        Row: {
          approved_at: string
          approved_by: string
          cash_holding_balance: number
          country_code: string
          created_at: string
          currency_code: string
          deactivated_at: string | null
          deactivated_by: string | null
          id: string
          is_active: boolean
          merchant_id: string
          receivable_balance: number
          updated_at: string
        }
        Insert: {
          approved_at?: string
          approved_by: string
          cash_holding_balance?: number
          country_code: string
          created_at?: string
          currency_code: string
          deactivated_at?: string | null
          deactivated_by?: string | null
          id?: string
          is_active?: boolean
          merchant_id: string
          receivable_balance?: number
          updated_at?: string
        }
        Update: {
          approved_at?: string
          approved_by?: string
          cash_holding_balance?: number
          country_code?: string
          created_at?: string
          currency_code?: string
          deactivated_at?: string | null
          deactivated_by?: string | null
          id?: string
          is_active?: boolean
          merchant_id?: string
          receivable_balance?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "credit_agent_account_approved_by_fkey"
            columns: ["approved_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_agent_account_deactivated_by_fkey"
            columns: ["deactivated_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_agent_account_merchant_id_fkey"
            columns: ["merchant_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_currency_code_fk"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
        ]
      }
      credit_agent_entry: {
        Row: {
          cash_holding_balance_after: number
          cash_holding_balance_before: number
          country_code: string
          created_at: string
          created_by: string
          credit_agent_account_id: string
          credit_cash_holding: number
          credit_receivable: number
          currency_code: string
          debit_cash_holding: number
          debit_receivable: number
          document_number: string
          fiscal_year: number
          id: string
          merchant_id: string
          period: number
          receivable_balance_after: number
          receivable_balance_before: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Insert: {
          cash_holding_balance_after: number
          cash_holding_balance_before: number
          country_code: string
          created_at?: string
          created_by: string
          credit_agent_account_id: string
          credit_cash_holding?: number
          credit_receivable?: number
          currency_code: string
          debit_cash_holding?: number
          debit_receivable?: number
          document_number: string
          fiscal_year: number
          id?: string
          merchant_id: string
          period: number
          receivable_balance_after: number
          receivable_balance_before: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Update: {
          cash_holding_balance_after?: number
          cash_holding_balance_before?: number
          country_code?: string
          created_at?: string
          created_by?: string
          credit_agent_account_id?: string
          credit_cash_holding?: number
          credit_receivable?: number
          currency_code?: string
          debit_cash_holding?: number
          debit_receivable?: number
          document_number?: string
          fiscal_year?: number
          id?: string
          merchant_id?: string
          period?: number
          receivable_balance_after?: number
          receivable_balance_before?: number
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
        }
        Relationships: [
          {
            foreignKeyName: "credit_agent_entry_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_agent_entry_credit_agent_account_id_fkey"
            columns: ["credit_agent_account_id"]
            isOneToOne: false
            referencedRelation: "credit_agent_account"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credit_agent_entry_document_number_fkey"
            columns: ["document_number"]
            isOneToOne: true
            referencedRelation: "financial_transaction"
            referencedColumns: ["document_number"]
          },
          {
            foreignKeyName: "credit_agent_entry_merchant_id_fkey"
            columns: ["merchant_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_country_fiscal_period_fk"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_currency_code_fk"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
        ]
      }
      current_rates: {
        Row: {
          code: string
          id: string
          rate_to_usd: number
          updated_at: string
        }
        Insert: {
          code: string
          id?: string
          rate_to_usd: number
          updated_at?: string
        }
        Update: {
          code?: string
          id?: string
          rate_to_usd?: number
          updated_at?: string
        }
        Relationships: []
      }
      device_tokens: {
        Row: {
          country_code: string
          created_at: string
          id: string
          platform: string
          token: string
          user_id: string
        }
        Insert: {
          country_code: string
          created_at?: string
          id?: string
          platform: string
          token: string
          user_id: string
        }
        Update: {
          country_code?: string
          created_at?: string
          id?: string
          platform?: string
          token?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_user_id_fk"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      document_sequence: {
        Row: {
          country_code: string
          created_at: string
          fiscal_year: number
          id: string
          last_number: number
          period: number
          prefix: string
        }
        Insert: {
          country_code: string
          created_at?: string
          fiscal_year: number
          id?: string
          last_number?: number
          period: number
          prefix: string
        }
        Update: {
          country_code?: string
          created_at?: string
          fiscal_year?: number
          id?: string
          last_number?: number
          period?: number
          prefix?: string
        }
        Relationships: [
          {
            foreignKeyName: "document_sequence_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      financial_badge: {
        Row: {
          behavior: Database["public"]["Enums"]["financial_behavior_type"]
          code: string
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          level: number
          metric: Database["public"]["Enums"]["financial_badge_metric"]
          name: string
          threshold_usd: number
          updated_at: string
        }
        Insert: {
          behavior: Database["public"]["Enums"]["financial_behavior_type"]
          code: string
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          level: number
          metric: Database["public"]["Enums"]["financial_badge_metric"]
          name: string
          threshold_usd: number
          updated_at?: string
        }
        Update: {
          behavior?: Database["public"]["Enums"]["financial_behavior_type"]
          code?: string
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          level?: number
          metric?: Database["public"]["Enums"]["financial_badge_metric"]
          name?: string
          threshold_usd?: number
          updated_at?: string
        }
        Relationships: []
      }
      financial_behavior: {
        Row: {
          behavior: Database["public"]["Enums"]["financial_behavior_type"]
          borrower_score_percentage: number
          borrowing_amount_usd: number
          borrowing_percentage: number
          calculated_at: string
          country_code: string
          created_at: string
          currency_code: string | null
          deposit_amount_usd: number
          fiscal_year: number
          id: string
          investment_amount_usd: number
          investment_percentage: number
          investor_score_percentage: number
          period: number | null
          repayment_amount_usd: number
          repayment_percentage: number
          rule_id: string | null
          saver_score_percentage: number
          saving_amount_usd: number
          saving_percentage: number
          scope: Database["public"]["Enums"]["financial_behavior_scope"]
          shopper_score_percentage: number
          spending_amount_usd: number
          spending_percentage: number
          updated_at: string
          user_id: string
          withdrawal_amount_usd: number
          withdrawal_percentage: number
        }
        Insert: {
          behavior: Database["public"]["Enums"]["financial_behavior_type"]
          borrower_score_percentage?: number
          borrowing_amount_usd?: number
          borrowing_percentage?: number
          calculated_at?: string
          country_code: string
          created_at?: string
          currency_code?: string | null
          deposit_amount_usd?: number
          fiscal_year: number
          id?: string
          investment_amount_usd?: number
          investment_percentage?: number
          investor_score_percentage?: number
          period?: number | null
          repayment_amount_usd?: number
          repayment_percentage?: number
          rule_id?: string | null
          saver_score_percentage?: number
          saving_amount_usd?: number
          saving_percentage?: number
          scope: Database["public"]["Enums"]["financial_behavior_scope"]
          shopper_score_percentage?: number
          spending_amount_usd?: number
          spending_percentage?: number
          updated_at?: string
          user_id: string
          withdrawal_amount_usd?: number
          withdrawal_percentage?: number
        }
        Update: {
          behavior?: Database["public"]["Enums"]["financial_behavior_type"]
          borrower_score_percentage?: number
          borrowing_amount_usd?: number
          borrowing_percentage?: number
          calculated_at?: string
          country_code?: string
          created_at?: string
          currency_code?: string | null
          deposit_amount_usd?: number
          fiscal_year?: number
          id?: string
          investment_amount_usd?: number
          investment_percentage?: number
          investor_score_percentage?: number
          period?: number | null
          repayment_amount_usd?: number
          repayment_percentage?: number
          rule_id?: string | null
          saver_score_percentage?: number
          saving_amount_usd?: number
          saving_percentage?: number
          scope?: Database["public"]["Enums"]["financial_behavior_scope"]
          shopper_score_percentage?: number
          spending_amount_usd?: number
          spending_percentage?: number
          updated_at?: string
          user_id?: string
          withdrawal_amount_usd?: number
          withdrawal_percentage?: number
        }
        Relationships: [
          {
            foreignKeyName: "financial_behavior_rule_id_fkey"
            columns: ["rule_id"]
            isOneToOne: false
            referencedRelation: "financial_behavior_rule"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_country_fiscal_period_fk"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_currency_code_fk"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "ngoda_user_id_fk"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      financial_behavior_rule: {
        Row: {
          behavior: Database["public"]["Enums"]["financial_behavior_type"]
          code: string
          conditions: Json
          created_at: string
          description: string | null
          id: string
          is_active: boolean
          name: string
          priority: number
          updated_at: string
        }
        Insert: {
          behavior: Database["public"]["Enums"]["financial_behavior_type"]
          code: string
          conditions?: Json
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name: string
          priority?: number
          updated_at?: string
        }
        Update: {
          behavior?: Database["public"]["Enums"]["financial_behavior_type"]
          code?: string
          conditions?: Json
          created_at?: string
          description?: string | null
          id?: string
          is_active?: boolean
          name?: string
          priority?: number
          updated_at?: string
        }
        Relationships: []
      }
      financial_entry: {
        Row: {
          country_code: string
          created_at: string
          created_by: string
          credit: number
          currency_code: string
          debit: number
          deposit_type:
            | Database["public"]["Enums"]["CustomerDepositType"]
            | null
          document_number: string
          fiscal_year: number
          gl_account_code: string
          id: number
          period: number
          reference: string | null
          transaction_id: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Insert: {
          country_code: string
          created_at?: string
          created_by: string
          credit?: number
          currency_code: string
          debit?: number
          deposit_type?:
            | Database["public"]["Enums"]["CustomerDepositType"]
            | null
          document_number: string
          fiscal_year: number
          gl_account_code: string
          id?: number
          period: number
          reference?: string | null
          transaction_id: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Update: {
          country_code?: string
          created_at?: string
          created_by?: string
          credit?: number
          currency_code?: string
          debit?: number
          deposit_type?:
            | Database["public"]["Enums"]["CustomerDepositType"]
            | null
          document_number?: string
          fiscal_year?: number
          gl_account_code?: string
          id?: number
          period?: number
          reference?: string | null
          transaction_id?: number
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
        }
        Relationships: [
          {
            foreignKeyName: "financial_entry_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "financial_entry_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "financial_entry_glAccount_code_fkey"
            columns: ["gl_account_code"]
            isOneToOne: false
            referencedRelation: "gl_account"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "financial_entry_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: false
            referencedRelation: "financial_transaction"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      financial_pot: {
        Row: {
          borrowing_percentage: number
          cash_in_amount: number
          cash_in_amount_usd: number
          closing_gold_quantity: number
          closing_investment_usd: number
          closing_loan_balance: number
          closing_loan_balance_usd: number
          closing_savings: number
          closing_savings_usd: number
          country_code: string
          created_at: string
          currency_code: string
          deposit_amount: number
          deposit_amount_usd: number
          fiscal_year: number
          gold_purchased: number
          gold_sold: number
          gold_transferred_in: number
          gold_transferred_out: number
          id: string
          investment_cash_amount: number
          investment_cash_amount_usd: number
          investment_inflow_usd: number
          investment_outflow_usd: number
          investment_percentage: number
          investment_proceeds_amount: number
          investment_proceeds_amount_usd: number
          investment_purchase_amount: number
          investment_purchase_amount_usd: number
          investment_sale_amount: number
          investment_sale_amount_usd: number
          loan_disbursed_amount: number
          loan_disbursed_amount_usd: number
          loan_interest_accrued: number
          loan_interest_accrued_usd: number
          loan_interest_repaid: number
          loan_interest_repaid_usd: number
          loan_principal_repaid: number
          loan_principal_repaid_usd: number
          loan_repayment_amount: number
          loan_repayment_amount_usd: number
          opening_gold_quantity: number
          opening_investment_usd: number
          opening_loan_balance: number
          opening_loan_balance_usd: number
          opening_savings: number
          opening_savings_usd: number
          period: number
          repayment_cash_amount: number
          repayment_cash_amount_usd: number
          repayment_percentage: number
          saving_amount: number
          saving_amount_usd: number
          saving_percentage: number
          savings_inflow: number
          savings_inflow_usd: number
          savings_outflow: number
          savings_outflow_usd: number
          spending_amount: number
          spending_amount_usd: number
          spending_cash_amount: number
          spending_cash_amount_usd: number
          spending_percentage: number
          transfer_in_amount: number
          transfer_in_amount_usd: number
          updated_at: string
          user_id: string
          withdrawal_amount: number
          withdrawal_amount_usd: number
          withdrawal_cash_amount: number
          withdrawal_cash_amount_usd: number
          withdrawal_percentage: number
        }
        Insert: {
          borrowing_percentage?: number
          cash_in_amount?: number
          cash_in_amount_usd?: number
          closing_gold_quantity?: number
          closing_investment_usd?: number
          closing_loan_balance?: number
          closing_loan_balance_usd?: number
          closing_savings?: number
          closing_savings_usd?: number
          country_code: string
          created_at?: string
          currency_code: string
          deposit_amount?: number
          deposit_amount_usd?: number
          fiscal_year: number
          gold_purchased?: number
          gold_sold?: number
          gold_transferred_in?: number
          gold_transferred_out?: number
          id?: string
          investment_cash_amount?: number
          investment_cash_amount_usd?: number
          investment_inflow_usd?: number
          investment_outflow_usd?: number
          investment_percentage?: number
          investment_proceeds_amount?: number
          investment_proceeds_amount_usd?: number
          investment_purchase_amount?: number
          investment_purchase_amount_usd?: number
          investment_sale_amount?: number
          investment_sale_amount_usd?: number
          loan_disbursed_amount?: number
          loan_disbursed_amount_usd?: number
          loan_interest_accrued?: number
          loan_interest_accrued_usd?: number
          loan_interest_repaid?: number
          loan_interest_repaid_usd?: number
          loan_principal_repaid?: number
          loan_principal_repaid_usd?: number
          loan_repayment_amount?: number
          loan_repayment_amount_usd?: number
          opening_gold_quantity?: number
          opening_investment_usd?: number
          opening_loan_balance?: number
          opening_loan_balance_usd?: number
          opening_savings?: number
          opening_savings_usd?: number
          period: number
          repayment_cash_amount?: number
          repayment_cash_amount_usd?: number
          repayment_percentage?: number
          saving_amount?: number
          saving_amount_usd?: number
          saving_percentage?: number
          savings_inflow?: number
          savings_inflow_usd?: number
          savings_outflow?: number
          savings_outflow_usd?: number
          spending_amount?: number
          spending_amount_usd?: number
          spending_cash_amount?: number
          spending_cash_amount_usd?: number
          spending_percentage?: number
          transfer_in_amount?: number
          transfer_in_amount_usd?: number
          updated_at?: string
          user_id: string
          withdrawal_amount?: number
          withdrawal_amount_usd?: number
          withdrawal_cash_amount?: number
          withdrawal_cash_amount_usd?: number
          withdrawal_percentage?: number
        }
        Update: {
          borrowing_percentage?: number
          cash_in_amount?: number
          cash_in_amount_usd?: number
          closing_gold_quantity?: number
          closing_investment_usd?: number
          closing_loan_balance?: number
          closing_loan_balance_usd?: number
          closing_savings?: number
          closing_savings_usd?: number
          country_code?: string
          created_at?: string
          currency_code?: string
          deposit_amount?: number
          deposit_amount_usd?: number
          fiscal_year?: number
          gold_purchased?: number
          gold_sold?: number
          gold_transferred_in?: number
          gold_transferred_out?: number
          id?: string
          investment_cash_amount?: number
          investment_cash_amount_usd?: number
          investment_inflow_usd?: number
          investment_outflow_usd?: number
          investment_percentage?: number
          investment_proceeds_amount?: number
          investment_proceeds_amount_usd?: number
          investment_purchase_amount?: number
          investment_purchase_amount_usd?: number
          investment_sale_amount?: number
          investment_sale_amount_usd?: number
          loan_disbursed_amount?: number
          loan_disbursed_amount_usd?: number
          loan_interest_accrued?: number
          loan_interest_accrued_usd?: number
          loan_interest_repaid?: number
          loan_interest_repaid_usd?: number
          loan_principal_repaid?: number
          loan_principal_repaid_usd?: number
          loan_repayment_amount?: number
          loan_repayment_amount_usd?: number
          opening_gold_quantity?: number
          opening_investment_usd?: number
          opening_loan_balance?: number
          opening_loan_balance_usd?: number
          opening_savings?: number
          opening_savings_usd?: number
          period?: number
          repayment_cash_amount?: number
          repayment_cash_amount_usd?: number
          repayment_percentage?: number
          saving_amount?: number
          saving_amount_usd?: number
          saving_percentage?: number
          savings_inflow?: number
          savings_inflow_usd?: number
          savings_outflow?: number
          savings_outflow_usd?: number
          spending_amount?: number
          spending_amount_usd?: number
          spending_cash_amount?: number
          spending_cash_amount_usd?: number
          spending_percentage?: number
          transfer_in_amount?: number
          transfer_in_amount_usd?: number
          updated_at?: string
          user_id?: string
          withdrawal_amount?: number
          withdrawal_amount_usd?: number
          withdrawal_cash_amount?: number
          withdrawal_cash_amount_usd?: number
          withdrawal_percentage?: number
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_country_fiscal_period_fk"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_currency_code_fk"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "ngoda_user_id_fk"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      financial_pot_event: {
        Row: {
          activity_type: Database["public"]["Enums"]["financial_activity_type"]
          amount: number
          amount_usd: number
          cash_amount: number
          cash_amount_usd: number
          country_code: string
          created_at: string
          currency_code: string
          fiscal_year: number
          gold_quantity: number
          id: string
          interest_amount: number
          interest_amount_usd: number
          investment_cost_usd: number
          period: number
          principal_amount: number
          principal_amount_usd: number
          reference: string
          transaction_type: string
          user_id: string
        }
        Insert: {
          activity_type: Database["public"]["Enums"]["financial_activity_type"]
          amount?: number
          amount_usd?: number
          cash_amount?: number
          cash_amount_usd?: number
          country_code: string
          created_at?: string
          currency_code: string
          fiscal_year: number
          gold_quantity?: number
          id?: string
          interest_amount?: number
          interest_amount_usd?: number
          investment_cost_usd?: number
          period: number
          principal_amount?: number
          principal_amount_usd?: number
          reference: string
          transaction_type: string
          user_id: string
        }
        Update: {
          activity_type?: Database["public"]["Enums"]["financial_activity_type"]
          amount?: number
          amount_usd?: number
          cash_amount?: number
          cash_amount_usd?: number
          country_code?: string
          created_at?: string
          currency_code?: string
          fiscal_year?: number
          gold_quantity?: number
          id?: string
          interest_amount?: number
          interest_amount_usd?: number
          investment_cost_usd?: number
          period?: number
          principal_amount?: number
          principal_amount_usd?: number
          reference?: string
          transaction_type?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_country_fiscal_period_fk"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_currency_code_fk"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "ngoda_user_id_fk"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      financial_transaction: {
        Row: {
          country_code: string
          created_at: string
          created_by: string
          currency_code: string
          description: string
          document_number: string
          external_reference: string | null
          fiscal_year: number
          gross_amount: number
          id: number
          period: number
          reference: string
          reversal_of: string | null
          reversed_by: string | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Insert: {
          country_code: string
          created_at?: string
          created_by: string
          currency_code: string
          description: string
          document_number: string
          external_reference?: string | null
          fiscal_year: number
          gross_amount?: number
          id?: number
          period: number
          reference: string
          reversal_of?: string | null
          reversed_by?: string | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Update: {
          country_code?: string
          created_at?: string
          created_by?: string
          currency_code?: string
          description?: string
          document_number?: string
          external_reference?: string | null
          fiscal_year?: number
          gross_amount?: number
          id?: number
          period?: number
          reference?: string
          reversal_of?: string | null
          reversed_by?: string | null
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
        }
        Relationships: [
          {
            foreignKeyName: "financial_transaction_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "financial_transaction_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      fiscal_period_config: {
        Row: {
          closing_date: string
          country_code: string
          created_at: string
          created_by: string
          fiscal_year: number
          id: string
          is_closed: boolean
          opening_date: string
          period: number
          period_name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          closing_date?: string
          country_code: string
          created_at?: string
          created_by: string
          fiscal_year: number
          id?: string
          is_closed?: boolean
          opening_date?: string
          period: number
          period_name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          closing_date?: string
          country_code?: string
          created_at?: string
          created_by?: string
          fiscal_year?: number
          id?: string
          is_closed?: boolean
          opening_date?: string
          period?: number
          period_name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      gamification_event: {
        Row: {
          amount: number | null
          amount_usd: number | null
          attempt_count: number
          claimed_at: string | null
          country_code: string | null
          created_at: string
          currency_code: string | null
          error_message: string | null
          event_type: Database["public"]["Enums"]["LoyaltyEventType"]
          id: string
          idempotency_key: string
          lease_expires_at: string | null
          metadata: Json
          processed_at: string | null
          reversal_event_id: string | null
          reversed_at: string | null
          source_reference: string
          source_transaction_id: string | null
          status: Database["public"]["Enums"]["GamificationEventStatus"]
          transaction_type:
            | Database["public"]["Enums"]["TransactionType"]
            | null
          updated_at: string
          user_id: string
        }
        Insert: {
          amount?: number | null
          amount_usd?: number | null
          attempt_count?: number
          claimed_at?: string | null
          country_code?: string | null
          created_at?: string
          currency_code?: string | null
          error_message?: string | null
          event_type: Database["public"]["Enums"]["LoyaltyEventType"]
          id?: string
          idempotency_key: string
          lease_expires_at?: string | null
          metadata?: Json
          processed_at?: string | null
          reversal_event_id?: string | null
          reversed_at?: string | null
          source_reference: string
          source_transaction_id?: string | null
          status?: Database["public"]["Enums"]["GamificationEventStatus"]
          transaction_type?:
            | Database["public"]["Enums"]["TransactionType"]
            | null
          updated_at?: string
          user_id: string
        }
        Update: {
          amount?: number | null
          amount_usd?: number | null
          attempt_count?: number
          claimed_at?: string | null
          country_code?: string | null
          created_at?: string
          currency_code?: string | null
          error_message?: string | null
          event_type?: Database["public"]["Enums"]["LoyaltyEventType"]
          id?: string
          idempotency_key?: string
          lease_expires_at?: string | null
          metadata?: Json
          processed_at?: string | null
          reversal_event_id?: string | null
          reversed_at?: string | null
          source_reference?: string
          source_transaction_id?: string | null
          status?: Database["public"]["Enums"]["GamificationEventStatus"]
          transaction_type?:
            | Database["public"]["Enums"]["TransactionType"]
            | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "gamification_event_reversal_event_id_fkey"
            columns: ["reversal_event_id"]
            isOneToOne: false
            referencedRelation: "gamification_event"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gamification_event_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_currency_code_fk"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
        ]
      }
      gamification_notification: {
        Row: {
          created_at: string
          display_priority: number
          displayed_at: string | null
          event_id: string | null
          id: string
          notification_type: Database["public"]["Enums"]["GamificationNotificationType"]
          payload: Json
          points: number
          seen_at: string | null
          subtitle: string | null
          title: string | null
          user_id: string
        }
        Insert: {
          created_at?: string
          display_priority?: number
          displayed_at?: string | null
          event_id?: string | null
          id?: string
          notification_type: Database["public"]["Enums"]["GamificationNotificationType"]
          payload?: Json
          points?: number
          seen_at?: string | null
          subtitle?: string | null
          title?: string | null
          user_id: string
        }
        Update: {
          created_at?: string
          display_priority?: number
          displayed_at?: string | null
          event_id?: string | null
          id?: string
          notification_type?: Database["public"]["Enums"]["GamificationNotificationType"]
          payload?: Json
          points?: number
          seen_at?: string | null
          subtitle?: string | null
          title?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "gamification_notification_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "gamification_event"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "gamification_notification_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      gl_account: {
        Row: {
          code: string
          created_at: string
          created_by: string
          currency_category: Database["public"]["Enums"]["CurrencyCategory"]
          description: string | null
          id: string
          is_active: boolean
          type: Database["public"]["Enums"]["GlType"]
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string
          currency_category: Database["public"]["Enums"]["CurrencyCategory"]
          description?: string | null
          id?: string
          is_active?: boolean
          type: Database["public"]["Enums"]["GlType"]
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string
          currency_category?: Database["public"]["Enums"]["CurrencyCategory"]
          description?: string | null
          id?: string
          is_active?: boolean
          type?: Database["public"]["Enums"]["GlType"]
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      gl_balance_snapshot: {
        Row: {
          closing_balance: number
          country_code: string
          created_at: string
          credit: number
          currency_code: string
          debit: number
          fiscal_year: number
          gl_account_code: string
          id: string
          opening_balance: number
          period: number
          updated_at: string
        }
        Insert: {
          closing_balance: number
          country_code: string
          created_at?: string
          credit: number
          currency_code: string
          debit: number
          fiscal_year: number
          gl_account_code: string
          id?: string
          opening_balance: number
          period: number
          updated_at?: string
        }
        Update: {
          closing_balance?: number
          country_code?: string
          created_at?: string
          credit?: number
          currency_code?: string
          debit?: number
          fiscal_year?: number
          gl_account_code?: string
          id?: string
          opening_balance?: number
          period?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "gl_balance_snapshot_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_country_fiscal_period_fk"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_gl_account_fk"
            columns: ["gl_account_code"]
            isOneToOne: false
            referencedRelation: "gl_account"
            referencedColumns: ["code"]
          },
        ]
      }
      gl_update_request: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          country_code: string
          created_at: string
          created_by: string
          currency_code: string
          fiscal_year: number
          id: string
          period: number
          quantity: number
          reason: string | null
          status: Database["public"]["Enums"]["GlUpdateStatus"]
          total_value: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          tx_hash: string | null
          uom: Database["public"]["Enums"]["Uom"]
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          country_code: string
          created_at?: string
          created_by: string
          currency_code: string
          fiscal_year: number
          id?: string
          period: number
          quantity: number
          reason?: string | null
          status?: Database["public"]["Enums"]["GlUpdateStatus"]
          total_value: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          tx_hash?: string | null
          uom?: Database["public"]["Enums"]["Uom"]
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          country_code?: string
          created_at?: string
          created_by?: string
          currency_code?: string
          fiscal_year?: number
          id?: string
          period?: number
          quantity?: number
          reason?: string | null
          status?: Database["public"]["Enums"]["GlUpdateStatus"]
          total_value?: number
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          tx_hash?: string | null
          uom?: Database["public"]["Enums"]["Uom"]
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "gl_update_request_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "gl_update_request_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      government_tax_config: {
        Row: {
          country_code: string
          created_at: string
          created_by: string
          currency_code: string
          fiscal_year: number
          fixed_amount: number | null
          id: string
          is_active: boolean
          max_amount: number | null
          min_amount: number | null
          period: number
          rate: number | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          country_code: string
          created_at?: string
          created_by?: string
          currency_code: string
          fiscal_year: number
          fixed_amount?: number | null
          id?: string
          is_active?: boolean
          max_amount?: number | null
          min_amount?: number | null
          period: number
          rate?: number | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          country_code?: string
          created_at?: string
          created_by?: string
          currency_code?: string
          fiscal_year?: number
          fixed_amount?: number | null
          id?: string
          is_active?: boolean
          max_amount?: number | null
          min_amount?: number | null
          period?: number
          rate?: number | null
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "government_tax_config_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      government_tax_payable: {
        Row: {
          country_code: string
          created_at: string
          currency_code: string
          document_number: string
          fiscal_year: number
          gross_amount: number
          id: string
          is_settled: boolean
          period: number
          reference: string | null
          settled_at: string | null
          settled_by: string | null
          settlement_batch_id: string | null
          tax_amount: number
          tax_rate: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Insert: {
          country_code: string
          created_at?: string
          currency_code: string
          document_number: string
          fiscal_year: number
          gross_amount: number
          id?: string
          is_settled?: boolean
          period: number
          reference?: string | null
          settled_at?: string | null
          settled_by?: string | null
          settlement_batch_id?: string | null
          tax_amount: number
          tax_rate: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Update: {
          country_code?: string
          created_at?: string
          currency_code?: string
          document_number?: string
          fiscal_year?: number
          gross_amount?: number
          id?: string
          is_settled?: boolean
          period?: number
          reference?: string | null
          settled_at?: string | null
          settled_by?: string | null
          settlement_batch_id?: string | null
          tax_amount?: number
          tax_rate?: number
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
        }
        Relationships: [
          {
            foreignKeyName: "government_tax_payable_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "government_tax_payable_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_settlement_batch_fk"
            columns: ["settlement_batch_id"]
            isOneToOne: false
            referencedRelation: "government_tax_settlement_batch"
            referencedColumns: ["id"]
          },
        ]
      }
      government_tax_settlement_batch: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          country_code: string
          created_at: string
          created_by: string
          currency_code: string
          document_number: string
          end_date: string
          error_message: string | null
          fiscal_year: number
          id: string
          paid_at: string | null
          period: number
          start_date: string
          status: Database["public"]["Enums"]["SettlementStatus"]
          total_amount: number
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          country_code: string
          created_at?: string
          created_by: string
          currency_code: string
          document_number: string
          end_date: string
          error_message?: string | null
          fiscal_year: number
          id?: string
          paid_at?: string | null
          period: number
          start_date: string
          status?: Database["public"]["Enums"]["SettlementStatus"]
          total_amount: number
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          country_code?: string
          created_at?: string
          created_by?: string
          currency_code?: string
          document_number?: string
          end_date?: string
          error_message?: string | null
          fiscal_year?: number
          id?: string
          paid_at?: string | null
          period?: number
          start_date?: string
          status?: Database["public"]["Enums"]["SettlementStatus"]
          total_amount?: number
        }
        Relationships: [
          {
            foreignKeyName: "government_tax_settlement_batch_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "government_tax_settlement_batch_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      government_tax_settlement_item: {
        Row: {
          batch_id: string
          country_code: string
          currency_code: string
          error_message: string | null
          fiscal_year: number
          gross_amount: number
          id: string
          paid_at: string | null
          period: number
          reference: string | null
          status: Database["public"]["Enums"]["SettlementStatus"]
          tax_amount: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Insert: {
          batch_id: string
          country_code: string
          currency_code: string
          error_message?: string | null
          fiscal_year: number
          gross_amount: number
          id?: string
          paid_at?: string | null
          period: number
          reference?: string | null
          status?: Database["public"]["Enums"]["SettlementStatus"]
          tax_amount: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Update: {
          batch_id?: string
          country_code?: string
          currency_code?: string
          error_message?: string | null
          fiscal_year?: number
          gross_amount?: number
          id?: string
          paid_at?: string | null
          period?: number
          reference?: string | null
          status?: Database["public"]["Enums"]["SettlementStatus"]
          tax_amount?: number
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
        }
        Relationships: [
          {
            foreignKeyName: "government_tax_settlement_item_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "government_tax_settlement_batch"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "government_tax_settlement_item_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "government_tax_settlement_item_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      idempotency_key: {
        Row: {
          country_code: string
          created_at: string
          endpoint: string
          expires_at: string | null
          fiscal_year: number
          id: string
          key: string
          method: string
          period: number
          response: Json
          status_code: number
          user_id: string | null
        }
        Insert: {
          country_code: string
          created_at?: string
          endpoint: string
          expires_at?: string | null
          fiscal_year: number
          id?: string
          key: string
          method: string
          period: number
          response: Json
          status_code: number
          user_id?: string | null
        }
        Update: {
          country_code?: string
          created_at?: string
          endpoint?: string
          expires_at?: string | null
          fiscal_year?: number
          id?: string
          key?: string
          method?: string
          period?: number
          response?: Json
          status_code?: number
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "idempotency_key_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_user_id_fk"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      job_error_log: {
        Row: {
          country_code: string
          created_at: string
          error: string
          id: string
          job_name: string
          reference: string | null
        }
        Insert: {
          country_code: string
          created_at?: string
          error: string
          id?: string
          job_name: string
          reference?: string | null
        }
        Update: {
          country_code?: string
          created_at?: string
          error?: string
          id?: string
          job_name?: string
          reference?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      liquidation_blockchain_queue: {
        Row: {
          attempt_count: number
          blockchain_code: string | null
          claimed_at: string | null
          collateral: number
          confirmed_at: string | null
          country_code: string
          created_at: string
          debt_repayment_amount: number | null
          document_number: string
          error_message: string | null
          explorer_url: string | null
          fiscal_year: number
          gold_price: number | null
          id: string
          last_attempt_at: string | null
          lease_expires_at: string | null
          liquidation_job_id: string | null
          manual_review_required: boolean
          penalty_amount: number | null
          period: number
          processing_started_at: string | null
          reason: string | null
          receiver_wallet_address: string | null
          reference: string | null
          retry_count: number
          sender_wallet_address: string | null
          signed_at: string | null
          signed_payload: Json | null
          status: Database["public"]["Enums"]["BlockchainLiquidationStatus"]
          submission_started_at: string | null
          submitted_at: string | null
          total_debt: number
          total_liquidation_proceeds: number | null
          treasury_id: string | null
          tx_hash: string | null
          updated_at: string
          user_id: string
          wallet_index: number
        }
        Insert: {
          attempt_count?: number
          blockchain_code?: string | null
          claimed_at?: string | null
          collateral: number
          confirmed_at?: string | null
          country_code: string
          created_at?: string
          debt_repayment_amount?: number | null
          document_number: string
          error_message?: string | null
          explorer_url?: string | null
          fiscal_year: number
          gold_price?: number | null
          id?: string
          last_attempt_at?: string | null
          lease_expires_at?: string | null
          liquidation_job_id?: string | null
          manual_review_required?: boolean
          penalty_amount?: number | null
          period: number
          processing_started_at?: string | null
          reason?: string | null
          receiver_wallet_address?: string | null
          reference?: string | null
          retry_count?: number
          sender_wallet_address?: string | null
          signed_at?: string | null
          signed_payload?: Json | null
          status: Database["public"]["Enums"]["BlockchainLiquidationStatus"]
          submission_started_at?: string | null
          submitted_at?: string | null
          total_debt: number
          total_liquidation_proceeds?: number | null
          treasury_id?: string | null
          tx_hash?: string | null
          updated_at?: string
          user_id: string
          wallet_index: number
        }
        Update: {
          attempt_count?: number
          blockchain_code?: string | null
          claimed_at?: string | null
          collateral?: number
          confirmed_at?: string | null
          country_code?: string
          created_at?: string
          debt_repayment_amount?: number | null
          document_number?: string
          error_message?: string | null
          explorer_url?: string | null
          fiscal_year?: number
          gold_price?: number | null
          id?: string
          last_attempt_at?: string | null
          lease_expires_at?: string | null
          liquidation_job_id?: string | null
          manual_review_required?: boolean
          penalty_amount?: number | null
          period?: number
          processing_started_at?: string | null
          reason?: string | null
          receiver_wallet_address?: string | null
          reference?: string | null
          retry_count?: number
          sender_wallet_address?: string | null
          signed_at?: string | null
          signed_payload?: Json | null
          status?: Database["public"]["Enums"]["BlockchainLiquidationStatus"]
          submission_started_at?: string | null
          submitted_at?: string | null
          total_debt?: number
          total_liquidation_proceeds?: number | null
          treasury_id?: string | null
          tx_hash?: string | null
          updated_at?: string
          user_id?: string
          wallet_index?: number
        }
        Relationships: [
          {
            foreignKeyName: "liquidation_blockchain_queue_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_blockchain_code_fk"
            columns: ["blockchain_code"]
            isOneToOne: false
            referencedRelation: "supported_blockchain"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_liquidation_job_fk"
            columns: ["liquidation_job_id"]
            isOneToOne: false
            referencedRelation: "liquidation_job"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ngoda_user_id_fk"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      liquidation_job: {
        Row: {
          accounting_retry_count: number
          accounting_started_at: string | null
          blockchain_code: string | null
          blockchain_queue_id: string | null
          collateral_required: number
          collateral_value: number
          completed_at: string | null
          country_code: string
          created_at: string
          document_number: string | null
          error_message: string | null
          fiscal_year: number
          gold_price: number | null
          id: string
          liquidation_ltv: number | null
          penalty_amount: number
          penalty_rate: number | null
          period: number
          repayment_required: number
          status: Database["public"]["Enums"]["LiquidationJobStatus"]
          target_ltv: number | null
          total_debt: number
          total_interest: number
          total_principal: number
          total_required: number
          user_id: string
        }
        Insert: {
          accounting_retry_count?: number
          accounting_started_at?: string | null
          blockchain_code?: string | null
          blockchain_queue_id?: string | null
          collateral_required: number
          collateral_value: number
          completed_at?: string | null
          country_code: string
          created_at?: string
          document_number?: string | null
          error_message?: string | null
          fiscal_year: number
          gold_price?: number | null
          id?: string
          liquidation_ltv?: number | null
          penalty_amount: number
          penalty_rate?: number | null
          period: number
          repayment_required: number
          status: Database["public"]["Enums"]["LiquidationJobStatus"]
          target_ltv?: number | null
          total_debt: number
          total_interest: number
          total_principal: number
          total_required: number
          user_id: string
        }
        Update: {
          accounting_retry_count?: number
          accounting_started_at?: string | null
          blockchain_code?: string | null
          blockchain_queue_id?: string | null
          collateral_required?: number
          collateral_value?: number
          completed_at?: string | null
          country_code?: string
          created_at?: string
          document_number?: string | null
          error_message?: string | null
          fiscal_year?: number
          gold_price?: number | null
          id?: string
          liquidation_ltv?: number | null
          penalty_amount?: number
          penalty_rate?: number | null
          period?: number
          repayment_required?: number
          status?: Database["public"]["Enums"]["LiquidationJobStatus"]
          target_ltv?: number | null
          total_debt?: number
          total_interest?: number
          total_principal?: number
          total_required?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "liquidation_job_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_blockchain_code_fk"
            columns: ["blockchain_code"]
            isOneToOne: false
            referencedRelation: "supported_blockchain"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "ngoda_blockchain_queue_fk"
            columns: ["blockchain_queue_id"]
            isOneToOne: false
            referencedRelation: "liquidation_blockchain_queue"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_user_id_fk"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      loan: {
        Row: {
          collateral: number
          country_code: string
          created_at: string
          currency_code: string
          document_number: string
          fiscal_year: number
          id: string
          initiation_fee: number
          interest_rate: number
          last_accrued_at: string | null
          liquidation_ltv: number
          liquidation_price: number
          max_ltv_percent: number
          net_amount: number
          period: number
          principal: number
          reference: string
          status: Database["public"]["Enums"]["LoanStatus"]
          updated_at: string
          user_id: string
        }
        Insert: {
          collateral: number
          country_code: string
          created_at?: string
          currency_code: string
          document_number: string
          fiscal_year: number
          id?: string
          initiation_fee: number
          interest_rate: number
          last_accrued_at?: string | null
          liquidation_ltv: number
          liquidation_price: number
          max_ltv_percent: number
          net_amount: number
          period: number
          principal: number
          reference: string
          status?: Database["public"]["Enums"]["LoanStatus"]
          updated_at?: string
          user_id: string
        }
        Update: {
          collateral?: number
          country_code?: string
          created_at?: string
          currency_code?: string
          document_number?: string
          fiscal_year?: number
          id?: string
          initiation_fee?: number
          interest_rate?: number
          last_accrued_at?: string | null
          liquidation_ltv?: number
          liquidation_price?: number
          max_ltv_percent?: number
          net_amount?: number
          period?: number
          principal?: number
          reference?: string
          status?: Database["public"]["Enums"]["LoanStatus"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "loan_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "loan_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "loan_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      loan_balance_snapshot: {
        Row: {
          closing_interest: number
          closing_principal: number
          country_code: string
          created_at: string
          credit_interest: number
          credit_principal: number
          debit_interest: number
          debit_principal: number
          fiscal_year: number
          id: string
          loan_id: string
          opening_interest: number
          opening_principal: number
          period: number
          updated_at: string
          user_id: string
        }
        Insert: {
          closing_interest: number
          closing_principal: number
          country_code: string
          created_at?: string
          credit_interest: number
          credit_principal: number
          debit_interest: number
          debit_principal: number
          fiscal_year: number
          id?: string
          loan_id: string
          opening_interest: number
          opening_principal: number
          period: number
          updated_at?: string
          user_id: string
        }
        Update: {
          closing_interest?: number
          closing_principal?: number
          country_code?: string
          created_at?: string
          credit_interest?: number
          credit_principal?: number
          debit_interest?: number
          debit_principal?: number
          fiscal_year?: number
          id?: string
          loan_id?: string
          opening_interest?: number
          opening_principal?: number
          period?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_country_fiscal_period_fk"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_loan_fk"
            columns: ["loan_id"]
            isOneToOne: false
            referencedRelation: "loan"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ngoda_user_id_fk"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      loan_config: {
        Row: {
          config_type: string
          country_code: string
          created_at: string
          created_by: string
          fiscal_year: number
          id: string
          is_active: boolean
          period: number
          rate: number | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          config_type: string
          country_code: string
          created_at?: string
          created_by?: string
          fiscal_year: number
          id?: string
          is_active?: boolean
          period: number
          rate?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          config_type?: string
          country_code?: string
          created_at?: string
          created_by?: string
          fiscal_year?: number
          id?: string
          is_active?: boolean
          period?: number
          rate?: number | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      loan_entry: {
        Row: {
          accrual_date: string | null
          collateralEntryId: number | null
          country_code: string
          created_at: string
          credit_interest: number
          credit_principal: number
          currency_code: string
          debit_interest: number
          debit_principal: number
          document_number: string
          entry_type: Database["public"]["Enums"]["LoanEntryType"]
          fiscal_year: number
          id: number
          loan_id: string
          period: number
          reference: string | null
        }
        Insert: {
          accrual_date?: string | null
          collateralEntryId?: number | null
          country_code: string
          created_at?: string
          credit_interest?: number
          credit_principal?: number
          currency_code: string
          debit_interest?: number
          debit_principal?: number
          document_number: string
          entry_type: Database["public"]["Enums"]["LoanEntryType"]
          fiscal_year: number
          id?: number
          loan_id: string
          period: number
          reference?: string | null
        }
        Update: {
          accrual_date?: string | null
          collateralEntryId?: number | null
          country_code?: string
          created_at?: string
          credit_interest?: number
          credit_principal?: number
          currency_code?: string
          debit_interest?: number
          debit_principal?: number
          document_number?: string
          entry_type?: Database["public"]["Enums"]["LoanEntryType"]
          fiscal_year?: number
          id?: number
          loan_id?: string
          period?: number
          reference?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "loan_entry_collateralEntryId_fkey"
            columns: ["collateralEntryId"]
            isOneToOne: false
            referencedRelation: "collateral_entry"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "loan_entry_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "loan_entry_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "loan_entry_loan_id_fkey"
            columns: ["loan_id"]
            isOneToOne: false
            referencedRelation: "loan"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      loyalty_account: {
        Row: {
          available_points: number
          created_at: string
          id: string
          is_active: boolean
          last_event_at: string | null
          level_code: string
          lifetime_earned_points: number
          tier_points: number
          updated_at: string
          user_id: string
        }
        Insert: {
          available_points?: number
          created_at?: string
          id?: string
          is_active?: boolean
          last_event_at?: string | null
          level_code?: string
          lifetime_earned_points?: number
          tier_points?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          available_points?: number
          created_at?: string
          id?: string
          is_active?: boolean
          last_event_at?: string | null
          level_code?: string
          lifetime_earned_points?: number
          tier_points?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "loyalty_account_level_code_fkey"
            columns: ["level_code"]
            isOneToOne: false
            referencedRelation: "loyalty_level"
            referencedColumns: ["level_code"]
          },
          {
            foreignKeyName: "loyalty_account_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      loyalty_badge: {
        Row: {
          badge_code: string
          category: Database["public"]["Enums"]["LoyaltyBadgeCategory"]
          created_at: string
          criteria_config: Json
          criteria_type: Database["public"]["Enums"]["LoyaltyBadgeCriteriaType"]
          description: string
          event_type: Database["public"]["Enums"]["LoyaltyEventType"] | null
          icon_key: string
          id: string
          is_active: boolean
          is_secret: boolean
          name: string
          sort_order: number
          target_value: number
          updated_at: string
          valid_from: string | null
          valid_until: string | null
        }
        Insert: {
          badge_code: string
          category: Database["public"]["Enums"]["LoyaltyBadgeCategory"]
          created_at?: string
          criteria_config?: Json
          criteria_type: Database["public"]["Enums"]["LoyaltyBadgeCriteriaType"]
          description: string
          event_type?: Database["public"]["Enums"]["LoyaltyEventType"] | null
          icon_key: string
          id?: string
          is_active?: boolean
          is_secret?: boolean
          name: string
          sort_order: number
          target_value: number
          updated_at?: string
          valid_from?: string | null
          valid_until?: string | null
        }
        Update: {
          badge_code?: string
          category?: Database["public"]["Enums"]["LoyaltyBadgeCategory"]
          created_at?: string
          criteria_config?: Json
          criteria_type?: Database["public"]["Enums"]["LoyaltyBadgeCriteriaType"]
          description?: string
          event_type?: Database["public"]["Enums"]["LoyaltyEventType"] | null
          icon_key?: string
          id?: string
          is_active?: boolean
          is_secret?: boolean
          name?: string
          sort_order?: number
          target_value?: number
          updated_at?: string
          valid_from?: string | null
          valid_until?: string | null
        }
        Relationships: []
      }
      loyalty_badge_progress: {
        Row: {
          badge_id: string
          completed_at: string | null
          created_at: string
          current_value: number
          id: string
          target_value: number
          updated_at: string
          user_id: string
        }
        Insert: {
          badge_id: string
          completed_at?: string | null
          created_at?: string
          current_value?: number
          id?: string
          target_value: number
          updated_at?: string
          user_id: string
        }
        Update: {
          badge_id?: string
          completed_at?: string | null
          created_at?: string
          current_value?: number
          id?: string
          target_value?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "loyalty_badge_progress_badge_id_fkey"
            columns: ["badge_id"]
            isOneToOne: false
            referencedRelation: "loyalty_badge"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "loyalty_badge_progress_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      loyalty_cap_usage: {
        Row: {
          id: string
          period_start: string
          period_type: Database["public"]["Enums"]["LoyaltyCapPeriodType"]
          points_awarded: number
          rule_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          id?: string
          period_start: string
          period_type: Database["public"]["Enums"]["LoyaltyCapPeriodType"]
          points_awarded?: number
          rule_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          id?: string
          period_start?: string
          period_type?: Database["public"]["Enums"]["LoyaltyCapPeriodType"]
          points_awarded?: number
          rule_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "loyalty_cap_usage_rule_id_fkey"
            columns: ["rule_id"]
            isOneToOne: false
            referencedRelation: "loyalty_rule"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "loyalty_cap_usage_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      loyalty_ledger: {
        Row: {
          available_balance_after: number
          created_at: string
          description: string | null
          event_id: string | null
          event_type: Database["public"]["Enums"]["LoyaltyEventType"] | null
          id: string
          ledger_type: Database["public"]["Enums"]["LoyaltyLedgerType"]
          loyalty_account_id: string
          metadata: Json
          points_delta: number
          reversal_of_ledger_id: string | null
          rule_id: string | null
          rule_snapshot: Json | null
          source_reference: string | null
          source_transaction_id: string | null
          tier_balance_after: number
          tier_points_delta: number
          user_id: string
        }
        Insert: {
          available_balance_after: number
          created_at?: string
          description?: string | null
          event_id?: string | null
          event_type?: Database["public"]["Enums"]["LoyaltyEventType"] | null
          id?: string
          ledger_type: Database["public"]["Enums"]["LoyaltyLedgerType"]
          loyalty_account_id: string
          metadata?: Json
          points_delta: number
          reversal_of_ledger_id?: string | null
          rule_id?: string | null
          rule_snapshot?: Json | null
          source_reference?: string | null
          source_transaction_id?: string | null
          tier_balance_after: number
          tier_points_delta?: number
          user_id: string
        }
        Update: {
          available_balance_after?: number
          created_at?: string
          description?: string | null
          event_id?: string | null
          event_type?: Database["public"]["Enums"]["LoyaltyEventType"] | null
          id?: string
          ledger_type?: Database["public"]["Enums"]["LoyaltyLedgerType"]
          loyalty_account_id?: string
          metadata?: Json
          points_delta?: number
          reversal_of_ledger_id?: string | null
          rule_id?: string | null
          rule_snapshot?: Json | null
          source_reference?: string | null
          source_transaction_id?: string | null
          tier_balance_after?: number
          tier_points_delta?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "loyalty_ledger_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "gamification_event"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "loyalty_ledger_loyalty_account_id_fkey"
            columns: ["loyalty_account_id"]
            isOneToOne: false
            referencedRelation: "loyalty_account"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "loyalty_ledger_reversal_of_ledger_id_fkey"
            columns: ["reversal_of_ledger_id"]
            isOneToOne: false
            referencedRelation: "loyalty_ledger"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "loyalty_ledger_rule_id_fkey"
            columns: ["rule_id"]
            isOneToOne: false
            referencedRelation: "loyalty_rule"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "loyalty_ledger_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      loyalty_level: {
        Row: {
          benefits: Json
          created_at: string
          id: string
          is_active: boolean
          level_code: string
          max_tier_points: number | null
          min_tier_points: number
          name: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          benefits?: Json
          created_at?: string
          id?: string
          is_active?: boolean
          level_code: string
          max_tier_points?: number | null
          min_tier_points: number
          name: string
          sort_order: number
          updated_at?: string
        }
        Update: {
          benefits?: Json
          created_at?: string
          id?: string
          is_active?: boolean
          level_code?: string
          max_tier_points?: number | null
          min_tier_points?: number
          name?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      loyalty_level_history: {
        Row: {
          created_at: string
          event_id: string | null
          id: string
          loyalty_account_id: string
          new_level_code: string
          previous_level_code: string | null
          reason: Database["public"]["Enums"]["LoyaltyLevelChangeReason"]
          tier_points: number
          user_id: string
        }
        Insert: {
          created_at?: string
          event_id?: string | null
          id?: string
          loyalty_account_id: string
          new_level_code: string
          previous_level_code?: string | null
          reason: Database["public"]["Enums"]["LoyaltyLevelChangeReason"]
          tier_points: number
          user_id: string
        }
        Update: {
          created_at?: string
          event_id?: string | null
          id?: string
          loyalty_account_id?: string
          new_level_code?: string
          previous_level_code?: string | null
          reason?: Database["public"]["Enums"]["LoyaltyLevelChangeReason"]
          tier_points?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "loyalty_level_history_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "gamification_event"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "loyalty_level_history_loyalty_account_id_fkey"
            columns: ["loyalty_account_id"]
            isOneToOne: false
            referencedRelation: "loyalty_account"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "loyalty_level_history_new_level_code_fkey"
            columns: ["new_level_code"]
            isOneToOne: false
            referencedRelation: "loyalty_level"
            referencedColumns: ["level_code"]
          },
          {
            foreignKeyName: "loyalty_level_history_previous_level_code_fkey"
            columns: ["previous_level_code"]
            isOneToOne: false
            referencedRelation: "loyalty_level"
            referencedColumns: ["level_code"]
          },
          {
            foreignKeyName: "loyalty_level_history_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      loyalty_program_config: {
        Row: {
          country_code: string | null
          created_at: string
          daily_points_cap: number
          id: string
          is_active: boolean
          monthly_points_cap: number
          points_expiry_months: number | null
          updated_at: string
        }
        Insert: {
          country_code?: string | null
          created_at?: string
          daily_points_cap?: number
          id?: string
          is_active?: boolean
          monthly_points_cap?: number
          points_expiry_months?: number | null
          updated_at?: string
        }
        Update: {
          country_code?: string | null
          created_at?: string
          daily_points_cap?: number
          id?: string
          is_active?: boolean
          monthly_points_cap?: number
          points_expiry_months?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      loyalty_redemption_config: {
        Row: {
          country_code: string | null
          created_at: string
          currency_code: string | null
          id: string
          is_active: boolean
          points_per_usd: number
          priority: number
          redemption_code: string
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at: string
          valid_from: string | null
          valid_until: string | null
        }
        Insert: {
          country_code?: string | null
          created_at?: string
          currency_code?: string | null
          id?: string
          is_active?: boolean
          points_per_usd: number
          priority?: number
          redemption_code: string
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          valid_from?: string | null
          valid_until?: string | null
        }
        Update: {
          country_code?: string | null
          created_at?: string
          currency_code?: string | null
          id?: string
          is_active?: boolean
          points_per_usd?: number
          priority?: number
          redemption_code?: string
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          valid_from?: string | null
          valid_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_currency_code_fk"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
        ]
      }
      loyalty_rule: {
        Row: {
          calculation_type: Database["public"]["Enums"]["LoyaltyRuleCalculationType"]
          condition_config: Json
          country_code: string | null
          created_at: string
          currency_code: string | null
          daily_cap_points: number | null
          event_type: Database["public"]["Enums"]["LoyaltyEventType"]
          fixed_points: number | null
          id: string
          is_active: boolean
          max_amount_usd: number | null
          max_points_per_event: number | null
          min_amount_usd: number | null
          min_points_per_event: number | null
          monthly_cap_points: number | null
          multiplier: number
          points_per_usd: number | null
          priority: number
          rule_code: string
          rule_name: string
          updated_at: string
          valid_from: string | null
          valid_until: string | null
        }
        Insert: {
          calculation_type: Database["public"]["Enums"]["LoyaltyRuleCalculationType"]
          condition_config?: Json
          country_code?: string | null
          created_at?: string
          currency_code?: string | null
          daily_cap_points?: number | null
          event_type: Database["public"]["Enums"]["LoyaltyEventType"]
          fixed_points?: number | null
          id?: string
          is_active?: boolean
          max_amount_usd?: number | null
          max_points_per_event?: number | null
          min_amount_usd?: number | null
          min_points_per_event?: number | null
          monthly_cap_points?: number | null
          multiplier?: number
          points_per_usd?: number | null
          priority?: number
          rule_code: string
          rule_name: string
          updated_at?: string
          valid_from?: string | null
          valid_until?: string | null
        }
        Update: {
          calculation_type?: Database["public"]["Enums"]["LoyaltyRuleCalculationType"]
          condition_config?: Json
          country_code?: string | null
          created_at?: string
          currency_code?: string | null
          daily_cap_points?: number | null
          event_type?: Database["public"]["Enums"]["LoyaltyEventType"]
          fixed_points?: number | null
          id?: string
          is_active?: boolean
          max_amount_usd?: number | null
          max_points_per_event?: number | null
          min_amount_usd?: number | null
          min_points_per_event?: number | null
          monthly_cap_points?: number | null
          multiplier?: number
          points_per_usd?: number | null
          priority?: number
          rule_code?: string
          rule_name?: string
          updated_at?: string
          valid_from?: string | null
          valid_until?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_currency_code_fk"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
        ]
      }
      loyalty_rule_band: {
        Row: {
          created_at: string
          fixed_points: number
          id: string
          max_amount_usd: number | null
          min_amount_usd: number
          points_per_usd: number
          rule_id: string
          sort_order: number
        }
        Insert: {
          created_at?: string
          fixed_points?: number
          id?: string
          max_amount_usd?: number | null
          min_amount_usd: number
          points_per_usd?: number
          rule_id: string
          sort_order: number
        }
        Update: {
          created_at?: string
          fixed_points?: number
          id?: string
          max_amount_usd?: number | null
          min_amount_usd?: number
          points_per_usd?: number
          rule_id?: string
          sort_order?: number
        }
        Relationships: [
          {
            foreignKeyName: "loyalty_rule_band_rule_id_fkey"
            columns: ["rule_id"]
            isOneToOne: false
            referencedRelation: "loyalty_rule"
            referencedColumns: ["id"]
          },
        ]
      }
      maximum_tap_payment_amount_config: {
        Row: {
          country_code: string
          created_at: string
          created_by: string
          currency_code: string
          id: string
          is_active: boolean
          max_amount: number
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          country_code: string
          created_at?: string
          created_by?: string
          currency_code: string
          id?: string
          is_active?: boolean
          max_amount: number
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          country_code?: string
          created_at?: string
          created_by?: string
          currency_code?: string
          id?: string
          is_active?: boolean
          max_amount?: number
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "maximum_tap_payment_amount_config_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      merchant_commission: {
        Row: {
          amount: number
          commission_amount: number
          commission_rate: number
          country_code: string
          created_at: string
          currency_code: string
          document_number: string
          fee_amount: number
          fiscal_year: number
          id: string
          is_settled: boolean
          merchant_id: string
          period: number
          reference: string | null
          settled_at: string | null
          settled_by: string | null
          settlement_batch_id: string | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Insert: {
          amount: number
          commission_amount: number
          commission_rate: number
          country_code: string
          created_at?: string
          currency_code: string
          document_number: string
          fee_amount: number
          fiscal_year: number
          id?: string
          is_settled?: boolean
          merchant_id: string
          period: number
          reference?: string | null
          settled_at?: string | null
          settled_by?: string | null
          settlement_batch_id?: string | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Update: {
          amount?: number
          commission_amount?: number
          commission_rate?: number
          country_code?: string
          created_at?: string
          currency_code?: string
          document_number?: string
          fee_amount?: number
          fiscal_year?: number
          id?: string
          is_settled?: boolean
          merchant_id?: string
          period?: number
          reference?: string | null
          settled_at?: string | null
          settled_by?: string | null
          settlement_batch_id?: string | null
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
        }
        Relationships: [
          {
            foreignKeyName: "merchant_commission_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "merchant_commission_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "merchant_commission_merchant_id_fkey"
            columns: ["merchant_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_settlement_batch_fk"
            columns: ["settlement_batch_id"]
            isOneToOne: false
            referencedRelation: "merchant_settlement_batch"
            referencedColumns: ["id"]
          },
        ]
      }
      merchant_fee_splitting_config: {
        Row: {
          company_rate: number
          country_code: string
          created_at: string
          created_by: string
          currency_code: string
          fiscal_year: number
          id: string
          is_active: boolean
          merchant_rate: number
          period: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          company_rate: number
          country_code: string
          created_at?: string
          created_by?: string
          currency_code: string
          fiscal_year: number
          id?: string
          is_active?: boolean
          merchant_rate: number
          period: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          company_rate?: number
          country_code?: string
          created_at?: string
          created_by?: string
          currency_code?: string
          fiscal_year?: number
          id?: string
          is_active?: boolean
          merchant_rate?: number
          period?: number
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "merchant_fee_splitting_config_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      merchant_settlement_batch: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          country_code: string
          created_at: string
          created_by: string
          currency_code: string
          document_number: string
          end_date: string
          error_message: string | null
          fiscal_year: number
          id: string
          paid_at: string | null
          period: number
          reference: string | null
          start_date: string
          status: Database["public"]["Enums"]["SettlementStatus"]
          total_amount: number
          total_merchants: number
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          country_code: string
          created_at?: string
          created_by: string
          currency_code: string
          document_number: string
          end_date: string
          error_message?: string | null
          fiscal_year: number
          id?: string
          paid_at?: string | null
          period: number
          reference?: string | null
          start_date: string
          status?: Database["public"]["Enums"]["SettlementStatus"]
          total_amount: number
          total_merchants: number
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          country_code?: string
          created_at?: string
          created_by?: string
          currency_code?: string
          document_number?: string
          end_date?: string
          error_message?: string | null
          fiscal_year?: number
          id?: string
          paid_at?: string | null
          period?: number
          reference?: string | null
          start_date?: string
          status?: Database["public"]["Enums"]["SettlementStatus"]
          total_amount?: number
          total_merchants?: number
        }
        Relationships: [
          {
            foreignKeyName: "merchant_settlement_batch_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "merchant_settlement_batch_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      merchant_settlement_item: {
        Row: {
          batch_id: string
          country_code: string
          currency_code: string
          error_message: string | null
          fiscal_year: number
          id: string
          merchant_id: string
          paid_at: string | null
          period: number
          status: Database["public"]["Enums"]["SettlementStatus"]
          total_commission: number
          total_fees_generated: number
          total_payment: number
        }
        Insert: {
          batch_id: string
          country_code: string
          currency_code: string
          error_message?: string | null
          fiscal_year: number
          id?: string
          merchant_id: string
          paid_at?: string | null
          period: number
          status?: Database["public"]["Enums"]["SettlementStatus"]
          total_commission: number
          total_fees_generated: number
          total_payment: number
        }
        Update: {
          batch_id?: string
          country_code?: string
          currency_code?: string
          error_message?: string | null
          fiscal_year?: number
          id?: string
          merchant_id?: string
          paid_at?: string | null
          period?: number
          status?: Database["public"]["Enums"]["SettlementStatus"]
          total_commission?: number
          total_fees_generated?: number
          total_payment?: number
        }
        Relationships: [
          {
            foreignKeyName: "merchant_settlement_item_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "merchant_settlement_batch"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "merchant_settlement_item_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "merchant_settlement_item_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "merchant_settlement_item_merchant_id_fkey"
            columns: ["merchant_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      message_translation: {
        Row: {
          created_at: string
          created_by: string
          id: string
          language_code: string
          message_key: string
          translated_text: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by: string
          id?: string
          language_code: string
          message_key: string
          translated_text: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          language_code?: string
          message_key?: string
          translated_text?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "message_translation_language_code_fkey"
            columns: ["language_code"]
            isOneToOne: false
            referencedRelation: "supported_language"
            referencedColumns: ["code"]
          },
        ]
      }
      notification_template: {
        Row: {
          audience: Database["public"]["Enums"]["NotificationAudience"]
          body_template: string
          country_code: string | null
          created_at: string
          id: string
          is_active: boolean
          language_code: string
          notification_type: Database["public"]["Enums"]["NotificationType"]
          title_template: string
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at: string
        }
        Insert: {
          audience: Database["public"]["Enums"]["NotificationAudience"]
          body_template: string
          country_code?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          language_code?: string
          notification_type: Database["public"]["Enums"]["NotificationType"]
          title_template: string
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
        }
        Update: {
          audience?: Database["public"]["Enums"]["NotificationAudience"]
          body_template?: string
          country_code?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          language_code?: string
          notification_type?: Database["public"]["Enums"]["NotificationType"]
          title_template?: string
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      notifications: {
        Row: {
          body: string
          country_code: string
          created_at: string
          delivered_at: string | null
          id: string
          is_delivered: boolean
          is_read: boolean
          notification_type: Database["public"]["Enums"]["NotificationType"]
          payload: Json
          read_at: string | null
          reference: string
          title: string
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          user_id: string
        }
        Insert: {
          body: string
          country_code: string
          created_at?: string
          delivered_at?: string | null
          id?: string
          is_delivered?: boolean
          is_read?: boolean
          notification_type: Database["public"]["Enums"]["NotificationType"]
          payload: Json
          read_at?: string | null
          reference: string
          title: string
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          user_id: string
        }
        Update: {
          body?: string
          country_code?: string
          created_at?: string
          delivered_at?: string | null
          id?: string
          is_delivered?: boolean
          is_read?: boolean
          notification_type?: Database["public"]["Enums"]["NotificationType"]
          payload?: Json
          read_at?: string | null
          reference?: string
          title?: string
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_user_id_fk"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      operational_country: {
        Row: {
          calling_code: string | null
          country_code: string
          created_at: string
          created_by: string
          id: string
          is_active: boolean
          name: string
          time_zone: string | null
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          calling_code?: string | null
          country_code: string
          created_at?: string
          created_by?: string
          id?: string
          is_active?: boolean
          name: string
          time_zone?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          calling_code?: string | null
          country_code?: string
          created_at?: string
          created_by?: string
          id?: string
          is_active?: boolean
          name?: string
          time_zone?: string | null
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      reconciliation_adjustment_request: {
        Row: {
          adjustment_type: Database["public"]["Enums"]["ReconciliationAdjustmentType"]
          approved_at: string | null
          approved_by: string | null
          country_code: string
          currency_code: string | null
          difference_amount: number
          document_number: string
          executed_at: string | null
          executed_by: string | null
          fiscal_year: number
          gl_account_code: string | null
          id: string
          item_id: string | null
          metadata: Json | null
          period: number
          reason: string
          reference: string | null
          rejected_at: string | null
          rejected_by: string | null
          rejection_reason: string | null
          requested_at: string
          requested_by: string
          resulting_document_number: string | null
          run_id: string | null
          source_name: string | null
          status: Database["public"]["Enums"]["ReconciliationAdjustmentStatus"]
          target_name: string | null
        }
        Insert: {
          adjustment_type: Database["public"]["Enums"]["ReconciliationAdjustmentType"]
          approved_at?: string | null
          approved_by?: string | null
          country_code: string
          currency_code?: string | null
          difference_amount: number
          document_number: string
          executed_at?: string | null
          executed_by?: string | null
          fiscal_year: number
          gl_account_code?: string | null
          id?: string
          item_id?: string | null
          metadata?: Json | null
          period: number
          reason: string
          reference?: string | null
          rejected_at?: string | null
          rejected_by?: string | null
          rejection_reason?: string | null
          requested_at?: string
          requested_by: string
          resulting_document_number?: string | null
          run_id?: string | null
          source_name?: string | null
          status?: Database["public"]["Enums"]["ReconciliationAdjustmentStatus"]
          target_name?: string | null
        }
        Update: {
          adjustment_type?: Database["public"]["Enums"]["ReconciliationAdjustmentType"]
          approved_at?: string | null
          approved_by?: string | null
          country_code?: string
          currency_code?: string | null
          difference_amount?: number
          document_number?: string
          executed_at?: string | null
          executed_by?: string | null
          fiscal_year?: number
          gl_account_code?: string | null
          id?: string
          item_id?: string | null
          metadata?: Json | null
          period?: number
          reason?: string
          reference?: string | null
          rejected_at?: string | null
          rejected_by?: string | null
          rejection_reason?: string | null
          requested_at?: string
          requested_by?: string
          resulting_document_number?: string | null
          run_id?: string | null
          source_name?: string | null
          status?: Database["public"]["Enums"]["ReconciliationAdjustmentStatus"]
          target_name?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_currency_code_fk"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "reconciliation_adjustment_request_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "reconciliation_adjustment_request_item_id_fkey"
            columns: ["item_id"]
            isOneToOne: false
            referencedRelation: "reconciliation_item"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reconciliation_adjustment_request_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "reconciliation_run"
            referencedColumns: ["id"]
          },
        ]
      }
      reconciliation_item: {
        Row: {
          check_type: Database["public"]["Enums"]["ReconciliationCheckType"]
          country_code: string
          created_at: string
          currency_code: string | null
          description: string | null
          difference_amount: number
          fiscal_year: number
          gl_account_code: string | null
          id: string
          metadata: Json | null
          period: number
          run_id: string
          source_amount: number
          source_name: string
          status: Database["public"]["Enums"]["ReconciliationStatus"]
          target_amount: number
          target_name: string
        }
        Insert: {
          check_type: Database["public"]["Enums"]["ReconciliationCheckType"]
          country_code: string
          created_at?: string
          currency_code?: string | null
          description?: string | null
          difference_amount: number
          fiscal_year: number
          gl_account_code?: string | null
          id?: string
          metadata?: Json | null
          period: number
          run_id: string
          source_amount: number
          source_name: string
          status?: Database["public"]["Enums"]["ReconciliationStatus"]
          target_amount: number
          target_name: string
        }
        Update: {
          check_type?: Database["public"]["Enums"]["ReconciliationCheckType"]
          country_code?: string
          created_at?: string
          currency_code?: string | null
          description?: string | null
          difference_amount?: number
          fiscal_year?: number
          gl_account_code?: string | null
          id?: string
          metadata?: Json | null
          period?: number
          run_id?: string
          source_amount?: number
          source_name?: string
          status?: Database["public"]["Enums"]["ReconciliationStatus"]
          target_amount?: number
          target_name?: string
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_country_fiscal_period_fk"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_currency_code_fk"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "reconciliation_item_run_id_fkey"
            columns: ["run_id"]
            isOneToOne: false
            referencedRelation: "reconciliation_run"
            referencedColumns: ["id"]
          },
        ]
      }
      reconciliation_run: {
        Row: {
          completed_at: string | null
          country_code: string
          created_at: string
          created_by: string
          failed_checks: number
          fiscal_year: number
          id: string
          notes: string | null
          passed_checks: number
          period: number
          reconciliation_date: string
          status: Database["public"]["Enums"]["ReconciliationStatus"]
          total_checks: number
        }
        Insert: {
          completed_at?: string | null
          country_code: string
          created_at?: string
          created_by: string
          failed_checks?: number
          fiscal_year: number
          id?: string
          notes?: string | null
          passed_checks?: number
          period: number
          reconciliation_date?: string
          status?: Database["public"]["Enums"]["ReconciliationStatus"]
          total_checks?: number
        }
        Update: {
          completed_at?: string | null
          country_code?: string
          created_at?: string
          created_by?: string
          failed_checks?: number
          fiscal_year?: number
          id?: string
          notes?: string | null
          passed_checks?: number
          period?: number
          reconciliation_date?: string
          status?: Database["public"]["Enums"]["ReconciliationStatus"]
          total_checks?: number
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "reconciliation_run_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
        ]
      }
      referral_earnings: {
        Row: {
          amount: number
          country_code: string
          created_at: string
          currency_code: string
          document_number: string
          earnings_rate: number
          fiscal_year: number
          id: string
          is_settled: boolean
          period: number
          reference: string | null
          settled_at: string | null
          settled_by: string | null
          settlement_batch_id: string | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          user_id: string
        }
        Insert: {
          amount: number
          country_code: string
          created_at?: string
          currency_code: string
          document_number: string
          earnings_rate: number
          fiscal_year: number
          id?: string
          is_settled?: boolean
          period: number
          reference?: string | null
          settled_at?: string | null
          settled_by?: string | null
          settlement_batch_id?: string | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          user_id: string
        }
        Update: {
          amount?: number
          country_code?: string
          created_at?: string
          currency_code?: string
          document_number?: string
          earnings_rate?: number
          fiscal_year?: number
          id?: string
          is_settled?: boolean
          period?: number
          reference?: string | null
          settled_at?: string | null
          settled_by?: string | null
          settlement_batch_id?: string | null
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_settlement_batch_fk"
            columns: ["settlement_batch_id"]
            isOneToOne: false
            referencedRelation: "referral_earnings_settlement_batch"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referral_earnings_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "referral_earnings_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "referral_earnings_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      referral_earnings_config: {
        Row: {
          country_code: string
          created_at: string
          created_by: string
          currency_code: string
          fiscal_year: number
          fixed_amount: number | null
          id: string
          is_active: boolean
          max_amount: number | null
          min_amount: number | null
          period: number
          rate: number | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          country_code: string
          created_at?: string
          created_by?: string
          currency_code: string
          fiscal_year: number
          fixed_amount?: number | null
          id?: string
          is_active?: boolean
          max_amount?: number | null
          min_amount?: number | null
          period: number
          rate?: number | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          country_code?: string
          created_at?: string
          created_by?: string
          currency_code?: string
          fiscal_year?: number
          fixed_amount?: number | null
          id?: string
          is_active?: boolean
          max_amount?: number | null
          min_amount?: number | null
          period?: number
          rate?: number | null
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "referral_earnings_config_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
        ]
      }
      referral_earnings_settlement_batch: {
        Row: {
          approved_at: string | null
          approved_by: string | null
          country_code: string
          created_at: string
          created_by: string
          currency_code: string
          document_number: string
          end_date: string
          error_message: string | null
          fiscal_year: number
          id: string
          paid_at: string | null
          period: number
          reference: string | null
          start_date: string
          status: Database["public"]["Enums"]["SettlementStatus"]
          total_amount: number
          total_users: number
        }
        Insert: {
          approved_at?: string | null
          approved_by?: string | null
          country_code: string
          created_at?: string
          created_by: string
          currency_code: string
          document_number: string
          end_date: string
          error_message?: string | null
          fiscal_year: number
          id?: string
          paid_at?: string | null
          period: number
          reference?: string | null
          start_date: string
          status?: Database["public"]["Enums"]["SettlementStatus"]
          total_amount: number
          total_users: number
        }
        Update: {
          approved_at?: string | null
          approved_by?: string | null
          country_code?: string
          created_at?: string
          created_by?: string
          currency_code?: string
          document_number?: string
          end_date?: string
          error_message?: string | null
          fiscal_year?: number
          id?: string
          paid_at?: string | null
          period?: number
          reference?: string | null
          start_date?: string
          status?: Database["public"]["Enums"]["SettlementStatus"]
          total_amount?: number
          total_users?: number
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "referral_earnings_settlement_batch_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "referral_earnings_settlement_batch_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
        ]
      }
      referral_earnings_settlement_item: {
        Row: {
          batch_id: string
          country_code: string
          currency_code: string
          error_message: string | null
          fiscal_year: number
          id: string
          paid_at: string | null
          period: number
          status: Database["public"]["Enums"]["SettlementStatus"]
          total_earnings: number
          user_id: string
        }
        Insert: {
          batch_id: string
          country_code: string
          currency_code: string
          error_message?: string | null
          fiscal_year: number
          id?: string
          paid_at?: string | null
          period: number
          status?: Database["public"]["Enums"]["SettlementStatus"]
          total_earnings: number
          user_id: string
        }
        Update: {
          batch_id?: string
          country_code?: string
          currency_code?: string
          error_message?: string | null
          fiscal_year?: number
          id?: string
          paid_at?: string | null
          period?: number
          status?: Database["public"]["Enums"]["SettlementStatus"]
          total_earnings?: number
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "referral_earnings_settlement_item_batch_id_fkey"
            columns: ["batch_id"]
            isOneToOne: false
            referencedRelation: "referral_earnings_settlement_batch"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "referral_earnings_settlement_item_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "referral_earnings_settlement_item_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "referral_earnings_settlement_item_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      reserve_asset_adjustment_request: {
        Row: {
          adjustment_type: Database["public"]["Enums"]["AssetAdjustmentType"]
          approved_at: string | null
          approved_by: string | null
          created_at: string
          created_by: string
          currency_code: string
          description: string
          document_number: string
          executed_at: string | null
          executed_by: string | null
          fiscal_year: number
          id: string
          period: number
          quantity: number
          reference: string | null
          status: Database["public"]["Enums"]["AdjustmentStatus"]
          total_value: number
          tx_hash: string | null
          uom: Database["public"]["Enums"]["Uom"]
        }
        Insert: {
          adjustment_type: Database["public"]["Enums"]["AssetAdjustmentType"]
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          created_by: string
          currency_code: string
          description: string
          document_number: string
          executed_at?: string | null
          executed_by?: string | null
          fiscal_year: number
          id?: string
          period: number
          quantity: number
          reference?: string | null
          status?: Database["public"]["Enums"]["AdjustmentStatus"]
          total_value: number
          tx_hash?: string | null
          uom?: Database["public"]["Enums"]["Uom"]
        }
        Update: {
          adjustment_type?: Database["public"]["Enums"]["AssetAdjustmentType"]
          approved_at?: string | null
          approved_by?: string | null
          created_at?: string
          created_by?: string
          currency_code?: string
          description?: string
          document_number?: string
          executed_at?: string | null
          executed_by?: string | null
          fiscal_year?: number
          id?: string
          period?: number
          quantity?: number
          reference?: string | null
          status?: Database["public"]["Enums"]["AdjustmentStatus"]
          total_value?: number
          tx_hash?: string | null
          uom?: Database["public"]["Enums"]["Uom"]
        }
        Relationships: [
          {
            foreignKeyName: "reserve_asset_adjustment_request_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
        ]
      }
      spread_config: {
        Row: {
          asset: Database["public"]["Enums"]["AssetType"]
          created_at: string
          direction: Database["public"]["Enums"]["SpreadDirection"]
          fiscal_year: number
          fixed_amount: number
          id: string
          is_active: boolean
          period: number
          rate: number
        }
        Insert: {
          asset: Database["public"]["Enums"]["AssetType"]
          created_at?: string
          direction: Database["public"]["Enums"]["SpreadDirection"]
          fiscal_year: number
          fixed_amount: number
          id?: string
          is_active?: boolean
          period: number
          rate: number
        }
        Update: {
          asset?: Database["public"]["Enums"]["AssetType"]
          created_at?: string
          direction?: Database["public"]["Enums"]["SpreadDirection"]
          fiscal_year?: number
          fixed_amount?: number
          id?: string
          is_active?: boolean
          period?: number
          rate?: number
        }
        Relationships: []
      }
      supported_blockchain: {
        Row: {
          blockchain_type: string
          code: string
          contract_address: string | null
          created_at: string
          id: string
          is_active: boolean
          name: string
          native_currency_code: string
          updated_at: string
        }
        Insert: {
          blockchain_type?: string
          code: string
          contract_address?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          native_currency_code: string
          updated_at?: string
        }
        Update: {
          blockchain_type?: string
          code?: string
          contract_address?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          native_currency_code?: string
          updated_at?: string
        }
        Relationships: []
      }
      supported_blockchain_network: {
        Row: {
          blockchain_id: string
          chain_id: number
          created_at: string
          environment: string
          explorer_url: string
          id: string
          is_active: boolean
          is_default: boolean
          network_name: string
          rpc_url: string | null
          treasury_wallet_address: string | null
          updated_at: string
        }
        Insert: {
          blockchain_id: string
          chain_id: number
          created_at?: string
          environment: string
          explorer_url: string
          id?: string
          is_active?: boolean
          is_default?: boolean
          network_name: string
          rpc_url?: string | null
          treasury_wallet_address?: string | null
          updated_at?: string
        }
        Update: {
          blockchain_id?: string
          chain_id?: number
          created_at?: string
          environment?: string
          explorer_url?: string
          id?: string
          is_active?: boolean
          is_default?: boolean
          network_name?: string
          rpc_url?: string | null
          treasury_wallet_address?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "supported_blockchain_network_blockchain_id_fkey"
            columns: ["blockchain_id"]
            isOneToOne: false
            referencedRelation: "supported_blockchain"
            referencedColumns: ["id"]
          },
        ]
      }
      supported_currency: {
        Row: {
          created_at: string
          created_by: string
          currency_category: Database["public"]["Enums"]["CurrencyCategory"]
          currency_code: string
          decimals: number
          id: string
          is_active: boolean
          name: string
          rate_api: string
          symbol: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string
          currency_category: Database["public"]["Enums"]["CurrencyCategory"]
          currency_code: string
          decimals?: number
          id?: string
          is_active?: boolean
          name: string
          rate_api: string
          symbol: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string
          currency_category?: Database["public"]["Enums"]["CurrencyCategory"]
          currency_code?: string
          decimals?: number
          id?: string
          is_active?: boolean
          name?: string
          rate_api?: string
          symbol?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      supported_language: {
        Row: {
          code: string
          created_at: string
          created_by: string
          id: string
          is_active: boolean
          is_default: boolean
          name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          code: string
          created_at?: string
          created_by?: string
          id?: string
          is_active?: boolean
          is_default?: boolean
          name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string
          id?: string
          is_active?: boolean
          is_default?: boolean
          name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      system_flag: {
        Row: {
          country_code: string
          fiscal_year: number
          flag_name: string
          id: string
          is_active: boolean
          period: number
          reason: string | null
          triggered_at: string
          triggered_by: string | null
        }
        Insert: {
          country_code: string
          fiscal_year: number
          flag_name: string
          id?: string
          is_active?: boolean
          period: number
          reason?: string | null
          triggered_at?: string
          triggered_by?: string | null
        }
        Update: {
          country_code?: string
          fiscal_year?: number
          flag_name?: string
          id?: string
          is_active?: boolean
          period?: number
          reason?: string | null
          triggered_at?: string
          triggered_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
        ]
      }
      tokenised_asset_adjustment_request: {
        Row: {
          adjustment_type: Database["public"]["Enums"]["TokenAdjustmentType"]
          approved_at: string | null
          approved_by: string | null
          blockchain_code: string | null
          created_at: string
          created_by: string
          currency_code: string
          description: string
          document_number: string
          executed_at: string | null
          executed_by: string | null
          fiscal_year: number
          id: string
          period: number
          quantity: number
          reference: string | null
          status: Database["public"]["Enums"]["AdjustmentStatus"]
          total_value: number
          tx_hash: string | null
          uom: Database["public"]["Enums"]["Uom"]
        }
        Insert: {
          adjustment_type: Database["public"]["Enums"]["TokenAdjustmentType"]
          approved_at?: string | null
          approved_by?: string | null
          blockchain_code?: string | null
          created_at?: string
          created_by: string
          currency_code: string
          description: string
          document_number: string
          executed_at?: string | null
          executed_by?: string | null
          fiscal_year: number
          id?: string
          period: number
          quantity: number
          reference?: string | null
          status?: Database["public"]["Enums"]["AdjustmentStatus"]
          total_value: number
          tx_hash?: string | null
          uom?: Database["public"]["Enums"]["Uom"]
        }
        Update: {
          adjustment_type?: Database["public"]["Enums"]["TokenAdjustmentType"]
          approved_at?: string | null
          approved_by?: string | null
          blockchain_code?: string | null
          created_at?: string
          created_by?: string
          currency_code?: string
          description?: string
          document_number?: string
          executed_at?: string | null
          executed_by?: string | null
          fiscal_year?: number
          id?: string
          period?: number
          quantity?: number
          reference?: string | null
          status?: Database["public"]["Enums"]["AdjustmentStatus"]
          total_value?: number
          tx_hash?: string | null
          uom?: Database["public"]["Enums"]["Uom"]
        }
        Relationships: [
          {
            foreignKeyName: "token_adjustment_blockchain_code_fk"
            columns: ["blockchain_code"]
            isOneToOne: false
            referencedRelation: "supported_blockchain"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "tokenised_asset_adjustment_request_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
        ]
      }
      transaction_gl_mapping: {
        Row: {
          component_type: Database["public"]["Enums"]["ComponentType"]
          created_at: string
          created_by: string
          credit_gl: string
          debit_gl: string
          id: string
          is_active: boolean
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          component_type: Database["public"]["Enums"]["ComponentType"]
          created_at?: string
          created_by?: string
          credit_gl: string
          debit_gl: string
          id?: string
          is_active?: boolean
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          component_type?: Database["public"]["Enums"]["ComponentType"]
          created_at?: string
          created_by?: string
          credit_gl?: string
          debit_gl?: string
          id?: string
          is_active?: boolean
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "transaction_gl_mapping_credit_gl_fkey"
            columns: ["credit_gl"]
            isOneToOne: false
            referencedRelation: "gl_account"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "transaction_gl_mapping_debit_gl_fkey"
            columns: ["debit_gl"]
            isOneToOne: false
            referencedRelation: "gl_account"
            referencedColumns: ["code"]
          },
        ]
      }
      transaction_limit: {
        Row: {
          country_code: string
          created_at: string
          created_by: string
          currency_code: string
          daily_limit: number
          fiscal_year: number
          id: string
          is_active: boolean
          kyc_status: Database["public"]["Enums"]["KycStatus"]
          max_amount: number
          min_amount: number
          monthly_limit: number
          period: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          country_code: string
          created_at?: string
          created_by?: string
          currency_code: string
          daily_limit: number
          fiscal_year: number
          id?: string
          is_active?: boolean
          kyc_status: Database["public"]["Enums"]["KycStatus"]
          max_amount: number
          min_amount: number
          monthly_limit: number
          period: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          country_code?: string
          created_at?: string
          created_by?: string
          currency_code?: string
          daily_limit?: number
          fiscal_year?: number
          id?: string
          is_active?: boolean
          kyc_status?: Database["public"]["Enums"]["KycStatus"]
          max_amount?: number
          min_amount?: number
          monthly_limit?: number
          period?: number
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "transaction_limit_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
        ]
      }
      transaction_state: {
        Row: {
          blockchain_code: string | null
          country_code: string
          created_at: string
          created_by: string
          gold_buy_preparation: Json | null
          gold_sell_preparation: Json | null
          id: string
          message: string | null
          payment_fee_contribution: boolean
          reference: string
          sender_approval: Json | null
          status: Database["public"]["Enums"]["TransactionStatus"]
          transaction_data: Json | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at: string
          user_id: string
        }
        Insert: {
          blockchain_code?: string | null
          country_code: string
          created_at?: string
          created_by: string
          gold_buy_preparation?: Json | null
          gold_sell_preparation?: Json | null
          id?: string
          message?: string | null
          payment_fee_contribution?: boolean
          reference: string
          sender_approval?: Json | null
          status?: Database["public"]["Enums"]["TransactionStatus"]
          transaction_data?: Json | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          user_id: string
        }
        Update: {
          blockchain_code?: string | null
          country_code?: string
          created_at?: string
          created_by?: string
          gold_buy_preparation?: Json | null
          gold_sell_preparation?: Json | null
          id?: string
          message?: string | null
          payment_fee_contribution?: boolean
          reference?: string
          sender_approval?: Json | null
          status?: Database["public"]["Enums"]["TransactionStatus"]
          transaction_data?: Json | null
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_blockchain_code_fk"
            columns: ["blockchain_code"]
            isOneToOne: false
            referencedRelation: "supported_blockchain"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_user_id_fk"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transaction_state_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      transaction_type_document_number_prefix: {
        Row: {
          document_number: string
          id: string
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Insert: {
          document_number: string
          id?: string
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Update: {
          document_number?: string
          id?: string
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
        }
        Relationships: []
      }
      transaction_type_fee_config: {
        Row: {
          country_code: string
          created_at: string
          created_by: string
          currency_code: string
          fiscal_year: number
          fixed_amount: number | null
          id: string
          is_active: boolean
          max_amount: number | null
          min_amount: number | null
          period: number
          rate: number | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          country_code: string
          created_at?: string
          created_by?: string
          currency_code: string
          fiscal_year: number
          fixed_amount?: number | null
          id?: string
          is_active?: boolean
          max_amount?: number | null
          min_amount?: number | null
          period: number
          rate?: number | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          country_code?: string
          created_at?: string
          created_by?: string
          currency_code?: string
          fiscal_year?: number
          fixed_amount?: number | null
          id?: string
          is_active?: boolean
          max_amount?: number | null
          min_amount?: number | null
          period?: number
          rate?: number | null
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "transaction_type_fee_config_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
        ]
      }
      transaction_type_wallet_owner: {
        Row: {
          audit_action_type: Database["public"]["Enums"]["AuditActionType"]
          id: string
          receiver_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
          sender_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Insert: {
          audit_action_type: Database["public"]["Enums"]["AuditActionType"]
          id?: string
          receiver_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
          sender_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Update: {
          audit_action_type?: Database["public"]["Enums"]["AuditActionType"]
          id?: string
          receiver_wallet_owner?: Database["public"]["Enums"]["WalletOwnerType"]
          sender_wallet_owner?: Database["public"]["Enums"]["WalletOwnerType"]
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
        }
        Relationships: []
      }
      transaction_types: {
        Row: {
          created_at: string
          created_by: string
          description: string | null
          id: string
          is_active: boolean
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string
          description?: string | null
          id?: string
          is_active?: boolean
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string
          description?: string | null
          id?: string
          is_active?: boolean
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      transaction_v: {
        Row: {
          created_at: string
          created_by: string
          id: string
          time: number
          updated_at: string
          updated_by: string | null
          v: string
        }
        Insert: {
          created_at?: string
          created_by?: string
          id?: string
          time: number
          updated_at?: string
          updated_by?: string | null
          v: string
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          time?: number
          updated_at?: string
          updated_by?: string | null
          v?: string
        }
        Relationships: []
      }
      user_badge: {
        Row: {
          awarded_at: string
          awarded_event_id: string | null
          badge_id: string
          id: string
          metadata: Json
          user_id: string
        }
        Insert: {
          awarded_at?: string
          awarded_event_id?: string | null
          badge_id: string
          id?: string
          metadata?: Json
          user_id: string
        }
        Update: {
          awarded_at?: string
          awarded_event_id?: string | null
          badge_id?: string
          id?: string
          metadata?: Json
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_badge_awarded_event_id_fkey"
            columns: ["awarded_event_id"]
            isOneToOne: false
            referencedRelation: "gamification_event"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_badge_badge_id_fkey"
            columns: ["badge_id"]
            isOneToOne: false
            referencedRelation: "loyalty_badge"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_badge_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      user_financial_badge: {
        Row: {
          achieved_at: string
          achieved_value_usd: number
          badge_id: string
          created_at: string
          fiscal_year: number | null
          id: string
          period: number | null
          user_id: string
        }
        Insert: {
          achieved_at?: string
          achieved_value_usd: number
          badge_id: string
          created_at?: string
          fiscal_year?: number | null
          id?: string
          period?: number | null
          user_id: string
        }
        Update: {
          achieved_at?: string
          achieved_value_usd?: number
          badge_id?: string
          created_at?: string
          fiscal_year?: number | null
          id?: string
          period?: number | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_user_id_fk"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_financial_badge_badge_id_fkey"
            columns: ["badge_id"]
            isOneToOne: false
            referencedRelation: "financial_badge"
            referencedColumns: ["id"]
          },
        ]
      }
      user_kyc: {
        Row: {
          created_at: string
          document_url: string | null
          expiry_date: string | null
          id: string
          id_number: string | null
          id_type: Database["public"]["Enums"]["KycDocumentType"] | null
          is_current: boolean
          kyc_status: Database["public"]["Enums"]["KycStatus"]
          occupation: string | null
          source_of_funds: string | null
          tax_number: string | null
          updated_at: string
          updated_by: string | null
          user_id: string
          verification_comments: string | null
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          created_at?: string
          document_url?: string | null
          expiry_date?: string | null
          id?: string
          id_number?: string | null
          id_type?: Database["public"]["Enums"]["KycDocumentType"] | null
          is_current?: boolean
          kyc_status?: Database["public"]["Enums"]["KycStatus"]
          occupation?: string | null
          source_of_funds?: string | null
          tax_number?: string | null
          updated_at?: string
          updated_by?: string | null
          user_id: string
          verification_comments?: string | null
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          created_at?: string
          document_url?: string | null
          expiry_date?: string | null
          id?: string
          id_number?: string | null
          id_type?: Database["public"]["Enums"]["KycDocumentType"] | null
          is_current?: boolean
          kyc_status?: Database["public"]["Enums"]["KycStatus"]
          occupation?: string | null
          source_of_funds?: string | null
          tax_number?: string | null
          updated_at?: string
          updated_by?: string | null
          user_id?: string
          verification_comments?: string | null
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "user_kyc_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      user_presence: {
        Row: {
          is_online: boolean
          last_seen_at: string
          user_id: string
        }
        Insert: {
          is_online?: boolean
          last_seen_at?: string
          user_id: string
        }
        Update: {
          is_online?: boolean
          last_seen_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_user_id_fk"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      user_role: {
        Row: {
          created_at: string
          description: string
          id: string
          name: string
          updated_at: string
          updated_by: string | null
        }
        Insert: {
          created_at?: string
          description: string
          id?: string
          name: string
          updated_at?: string
          updated_by?: string | null
        }
        Update: {
          created_at?: string
          description?: string
          id?: string
          name?: string
          updated_at?: string
          updated_by?: string | null
        }
        Relationships: []
      }
      user_verification_document: {
        Row: {
          created_at: string
          document_type: Database["public"]["Enums"]["VerificationDocumentType"]
          file_name: string | null
          id: string
          status: Database["public"]["Enums"]["KycStatus"]
          updated_at: string
          updated_by: string | null
          uploaded_at: string
          url: string
          user_id: string
          verified_at: string | null
          verified_by: string | null
        }
        Insert: {
          created_at?: string
          document_type: Database["public"]["Enums"]["VerificationDocumentType"]
          file_name?: string | null
          id?: string
          status?: Database["public"]["Enums"]["KycStatus"]
          updated_at?: string
          updated_by?: string | null
          uploaded_at?: string
          url: string
          user_id: string
          verified_at?: string | null
          verified_by?: string | null
        }
        Update: {
          created_at?: string
          document_type?: Database["public"]["Enums"]["VerificationDocumentType"]
          file_name?: string | null
          id?: string
          status?: Database["public"]["Enums"]["KycStatus"]
          updated_at?: string
          updated_by?: string | null
          uploaded_at?: string
          url?: string
          user_id?: string
          verified_at?: string | null
          verified_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "user_verification_document_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      users: {
        Row: {
          city: string | null
          country_code: string
          created_at: string
          dob: string | null
          email: string | null
          first_name: string | null
          gender: Database["public"]["Enums"]["GenderType"] | null
          id: string
          middle_name: string | null
          nationality: string | null
          phone: string | null
          preferred_language: string
          province_state: string | null
          referral_code: string
          residential_address: string | null
          role_id: string
          status: Database["public"]["Enums"]["UserStatus"]
          surname: string | null
          updated_at: string
          upliner: string | null
          wallet_address: string
          wallet_index: number
        }
        Insert: {
          city?: string | null
          country_code: string
          created_at?: string
          dob?: string | null
          email?: string | null
          first_name?: string | null
          gender?: Database["public"]["Enums"]["GenderType"] | null
          id: string
          middle_name?: string | null
          nationality?: string | null
          phone?: string | null
          preferred_language?: string
          province_state?: string | null
          referral_code: string
          residential_address?: string | null
          role_id: string
          status?: Database["public"]["Enums"]["UserStatus"]
          surname?: string | null
          updated_at?: string
          upliner?: string | null
          wallet_address: string
          wallet_index: number
        }
        Update: {
          city?: string | null
          country_code?: string
          created_at?: string
          dob?: string | null
          email?: string | null
          first_name?: string | null
          gender?: Database["public"]["Enums"]["GenderType"] | null
          id?: string
          middle_name?: string | null
          nationality?: string | null
          phone?: string | null
          preferred_language?: string
          province_state?: string | null
          referral_code?: string
          residential_address?: string | null
          role_id?: string
          status?: Database["public"]["Enums"]["UserStatus"]
          surname?: string | null
          updated_at?: string
          upliner?: string | null
          wallet_address?: string
          wallet_index?: number
        }
        Relationships: [
          {
            foreignKeyName: "users_country_code_fkey"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "users_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "user_role"
            referencedColumns: ["id"]
          },
        ]
      }
      voucher_lock: {
        Row: {
          locked_at: string
          voucher_reference: string
        }
        Insert: {
          locked_at?: string
          voucher_reference: string
        }
        Update: {
          locked_at?: string
          voucher_reference?: string
        }
        Relationships: []
      }
      voucher_usage: {
        Row: {
          created_at: string
          credit: number
          debit: number
          id: string
          merchant_id: string
          message: string | null
          reference: string
          status: Database["public"]["Enums"]["TransactionStatus"]
          transaction_data: Json
          voucher_data: Json
          voucher_reference: string
        }
        Insert: {
          created_at?: string
          credit: number
          debit: number
          id?: string
          merchant_id: string
          message?: string | null
          reference: string
          status: Database["public"]["Enums"]["TransactionStatus"]
          transaction_data: Json
          voucher_data: Json
          voucher_reference: string
        }
        Update: {
          created_at?: string
          credit?: number
          debit?: number
          id?: string
          merchant_id?: string
          message?: string | null
          reference?: string
          status?: Database["public"]["Enums"]["TransactionStatus"]
          transaction_data?: Json
          voucher_data?: Json
          voucher_reference?: string
        }
        Relationships: []
      }
      wallet: {
        Row: {
          balance: number
          blockchain_code: string | null
          country_code: string
          created_at: string
          currency_code: string
          id: string
          is_active: boolean
          owner_type: Database["public"]["Enums"]["WalletOwnerType"]
          updated_at: string
          user_id: string
        }
        Insert: {
          balance: number
          blockchain_code?: string | null
          country_code: string
          created_at?: string
          currency_code: string
          id?: string
          is_active?: boolean
          owner_type: Database["public"]["Enums"]["WalletOwnerType"]
          updated_at?: string
          user_id: string
        }
        Update: {
          balance?: number
          blockchain_code?: string | null
          country_code?: string
          created_at?: string
          currency_code?: string
          id?: string
          is_active?: boolean
          owner_type?: Database["public"]["Enums"]["WalletOwnerType"]
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "wallet_blockchain_code_fkey"
            columns: ["blockchain_code"]
            isOneToOne: false
            referencedRelation: "supported_blockchain"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "wallet_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "wallet_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      wallet_balance_snapshot: {
        Row: {
          blockchain_code: string | null
          closing_balance: number
          country_code: string
          created_at: string
          credit: number
          currency_code: string
          debit: number
          fiscal_year: number
          id: string
          opening_balance: number
          period: number
          updated_at: string
          user_id: string
          wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
        }
        Insert: {
          blockchain_code?: string | null
          closing_balance: number
          country_code: string
          created_at?: string
          credit: number
          currency_code: string
          debit: number
          fiscal_year: number
          id?: string
          opening_balance: number
          period: number
          updated_at?: string
          user_id: string
          wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
        }
        Update: {
          blockchain_code?: string | null
          closing_balance?: number
          country_code?: string
          created_at?: string
          credit?: number
          currency_code?: string
          debit?: number
          fiscal_year?: number
          id?: string
          opening_balance?: number
          period?: number
          updated_at?: string
          user_id?: string
          wallet_owner?: Database["public"]["Enums"]["WalletOwnerType"]
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "ngoda_country_fiscal_period_fk"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "ngoda_user_id_fk"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wallet_balance_snapshot_blockchain_code_fkey"
            columns: ["blockchain_code"]
            isOneToOne: false
            referencedRelation: "supported_blockchain"
            referencedColumns: ["code"]
          },
          {
            foreignKeyName: "wallet_balance_snapshot_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
        ]
      }
      wallet_entry: {
        Row: {
          blockchain_code: string | null
          country_code: string
          created_at: string
          created_by: string
          credit: number | null
          currency_code: string
          debit: number | null
          document_number: string
          fiscal_year: number
          id: number
          period: number
          reference: string | null
          transaction_id: number | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          wallet_id: string
        }
        Insert: {
          blockchain_code?: string | null
          country_code: string
          created_at?: string
          created_by: string
          credit?: number | null
          currency_code: string
          debit?: number | null
          document_number: string
          fiscal_year: number
          id?: number
          period: number
          reference?: string | null
          transaction_id?: number | null
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          wallet_id: string
        }
        Update: {
          blockchain_code?: string | null
          country_code?: string
          created_at?: string
          created_by?: string
          credit?: number | null
          currency_code?: string
          debit?: number | null
          document_number?: string
          fiscal_year?: number
          id?: number
          period?: number
          reference?: string | null
          transaction_id?: number | null
          transaction_type?: Database["public"]["Enums"]["TransactionType"]
          wallet_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "ngoda_country_code_fk"
            columns: ["country_code"]
            isOneToOne: false
            referencedRelation: "operational_country"
            referencedColumns: ["country_code"]
          },
          {
            foreignKeyName: "wallet_entry_currency_code_fkey"
            columns: ["currency_code"]
            isOneToOne: false
            referencedRelation: "supported_currency"
            referencedColumns: ["currency_code"]
          },
          {
            foreignKeyName: "wallet_entry_fiscal_year_period_fkey"
            columns: ["country_code", "fiscal_year", "period"]
            isOneToOne: false
            referencedRelation: "fiscal_period_config"
            referencedColumns: ["country_code", "fiscal_year", "period"]
          },
          {
            foreignKeyName: "wallet_entry_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: false
            referencedRelation: "financial_transaction"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wallet_entry_wallet_id_fkey"
            columns: ["wallet_id"]
            isOneToOne: false
            referencedRelation: "wallet"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      accrue_daily_interest_for_loan: {
        Args: { p_accrual_date: string; p_loan_id: string }
        Returns: boolean
      }
      acknowledge_my_gamification_notification: {
        Args: { p_mark_seen?: boolean; p_notification_id: string }
        Returns: Json
      }
      apply_gl_snapshot_update: {
        Args: {
          p_country_code: string
          p_credit: number
          p_currency_code: string
          p_debit: number
          p_fiscal_year: number
          p_gl_account_code: string
          p_period: number
        }
        Returns: undefined
      }
      apply_wallet_snapshot_update: {
        Args: {
          p_blockchain_code?: string
          p_country_code: string
          p_credit: number
          p_currency_code: string
          p_debit: number
          p_fiscal_year: number
          p_period: number
          p_user_id: string
          p_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
        }
        Returns: undefined
      }
      approve_my_credit_agent: {
        Args: { p_merchant_identifier: string }
        Returns: Json
      }
      award_loyalty_points: {
        Args: {
          p_amount?: number
          p_amount_usd?: number
          p_country_code?: string
          p_currency_code?: string
          p_event_type: Database["public"]["Enums"]["LoyaltyEventType"]
          p_idempotency_key: string
          p_metadata?: Json
          p_source_reference: string
          p_source_transaction_id?: string
          p_transaction_type?: Database["public"]["Enums"]["TransactionType"]
          p_user_id: string
        }
        Returns: Json
      }
      begin_liquidation_blockchain_submission: {
        Args: { p_queue_id: string; p_signed_payload: Json }
        Returns: Json
      }
      build_country_supported_currencies: {
        Args: { p_country_code: string }
        Returns: Json
      }
      build_gold_buy_components_from_pricing: {
        Args: {
          p_mappings: Database["public"]["Tables"]["transaction_gl_mapping"]["Row"][]
          p_pricing: Database["public"]["CompositeTypes"]["pricing_result"]
          p_principal: number
          p_reverse?: boolean
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: Database["public"]["CompositeTypes"]["posting_component"][]
      }
      build_gold_buy_recovery_context: {
        Args: { p_blockchain_transaction_id: string; p_executor_id: string }
        Returns: Json
      }
      build_gold_sell_components_from_pricing: {
        Args: {
          p_mappings: Database["public"]["Tables"]["transaction_gl_mapping"]["Row"][]
          p_pricing: Database["public"]["CompositeTypes"]["pricing_result"]
          p_principal: number
          p_reverse?: boolean
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: Database["public"]["CompositeTypes"]["posting_component"][]
      }
      build_gold_sell_recovery_context: {
        Args: { p_blockchain_transaction_id: string; p_executor_id: string }
        Returns: Json
      }
      build_my_accounts_dashboard: { Args: never; Returns: Json }
      build_my_admin_dashboard: { Args: never; Returns: Json }
      build_my_agent_dashboard: {
        Args: { p_blockchain_balances: Json }
        Returns: Json
      }
      build_my_compliance_dashboard: { Args: never; Returns: Json }
      build_my_customer_dashboard: {
        Args: { p_blockchain_balances: Json }
        Returns: Json
      }
      build_my_finance_dashboard: { Args: never; Returns: Json }
      build_my_merchant_dashboard: { Args: never; Returns: Json }
      build_my_treasury_dashboard: {
        Args: { p_blockchain_balances: Json }
        Returns: Json
      }
      build_my_vendor_dashboard: {
        Args: { p_blockchain_balances: Json }
        Returns: Json
      }
      build_posting_components: {
        Args: {
          p_country_code: string
          p_currency_code: string
          p_mappings: Database["public"]["Tables"]["transaction_gl_mapping"]["Row"][]
          p_principal: number
          p_reverse?: boolean
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: Database["public"]["CompositeTypes"]["posting_component"][]
      }
      build_principal_component: {
        Args: {
          p_charges: number
          p_principal: number
          p_principal_mode: Database["public"]["Enums"]["PrincipalMode"]
          p_reverse?: boolean
        }
        Returns: Database["public"]["CompositeTypes"]["posting_component"]
        SetofOptions: {
          from: "*"
          to: "posting_component"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      build_user_daily_summary: { Args: { p_user_id: string }; Returns: Json }
      build_user_wallet_balance: { Args: { p_user_id: string }; Returns: Json }
      calculate_configured_amount: {
        Args: {
          p_amount: number
          p_config?: Database["public"]["CompositeTypes"]["amount_config"]
        }
        Returns: number
      }
      calculate_financial_behavior: {
        Args: {
          p_country_code: string
          p_currency_code: string
          p_fiscal_year: number
          p_period: number
          p_user_id: string
        }
        Returns: Json
      }
      calculate_financial_behavior_snapshot: {
        Args: {
          p_country_code: string
          p_currency_code: string
          p_fiscal_year: number
          p_period: number
          p_scope: Database["public"]["Enums"]["financial_behavior_scope"]
          p_user_id: string
        }
        Returns: {
          behavior: Database["public"]["Enums"]["financial_behavior_type"]
          borrower_score_percentage: number
          borrowing_amount_usd: number
          borrowing_percentage: number
          calculated_at: string
          country_code: string
          created_at: string
          currency_code: string | null
          deposit_amount_usd: number
          fiscal_year: number
          id: string
          investment_amount_usd: number
          investment_percentage: number
          investor_score_percentage: number
          period: number | null
          repayment_amount_usd: number
          repayment_percentage: number
          rule_id: string | null
          saver_score_percentage: number
          saving_amount_usd: number
          saving_percentage: number
          scope: Database["public"]["Enums"]["financial_behavior_scope"]
          shopper_score_percentage: number
          spending_amount_usd: number
          spending_percentage: number
          updated_at: string
          user_id: string
          withdrawal_amount_usd: number
          withdrawal_percentage: number
        }
        SetofOptions: {
          from: "*"
          to: "financial_behavior"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      calculate_financial_pot_percentages: {
        Args: {
          p_currency_code: string
          p_fiscal_year: number
          p_period: number
          p_user_id: string
        }
        Returns: {
          borrowing_percentage: number
          cash_in_amount: number
          cash_in_amount_usd: number
          closing_gold_quantity: number
          closing_investment_usd: number
          closing_loan_balance: number
          closing_loan_balance_usd: number
          closing_savings: number
          closing_savings_usd: number
          country_code: string
          created_at: string
          currency_code: string
          deposit_amount: number
          deposit_amount_usd: number
          fiscal_year: number
          gold_purchased: number
          gold_sold: number
          gold_transferred_in: number
          gold_transferred_out: number
          id: string
          investment_cash_amount: number
          investment_cash_amount_usd: number
          investment_inflow_usd: number
          investment_outflow_usd: number
          investment_percentage: number
          investment_proceeds_amount: number
          investment_proceeds_amount_usd: number
          investment_purchase_amount: number
          investment_purchase_amount_usd: number
          investment_sale_amount: number
          investment_sale_amount_usd: number
          loan_disbursed_amount: number
          loan_disbursed_amount_usd: number
          loan_interest_accrued: number
          loan_interest_accrued_usd: number
          loan_interest_repaid: number
          loan_interest_repaid_usd: number
          loan_principal_repaid: number
          loan_principal_repaid_usd: number
          loan_repayment_amount: number
          loan_repayment_amount_usd: number
          opening_gold_quantity: number
          opening_investment_usd: number
          opening_loan_balance: number
          opening_loan_balance_usd: number
          opening_savings: number
          opening_savings_usd: number
          period: number
          repayment_cash_amount: number
          repayment_cash_amount_usd: number
          repayment_percentage: number
          saving_amount: number
          saving_amount_usd: number
          saving_percentage: number
          savings_inflow: number
          savings_inflow_usd: number
          savings_outflow: number
          savings_outflow_usd: number
          spending_amount: number
          spending_amount_usd: number
          spending_cash_amount: number
          spending_cash_amount_usd: number
          spending_percentage: number
          transfer_in_amount: number
          transfer_in_amount_usd: number
          updated_at: string
          user_id: string
          withdrawal_amount: number
          withdrawal_amount_usd: number
          withdrawal_cash_amount: number
          withdrawal_cash_amount_usd: number
          withdrawal_percentage: number
        }
        SetofOptions: {
          from: "*"
          to: "financial_pot"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      calculate_gold_buy_execution_pricing: {
        Args: {
          p_amount: number
          p_country_code: string
          p_currency_code: string
        }
        Returns: Json
      }
      calculate_gold_buy_pricing: {
        Args: {
          p_amount: number
          p_country_code: string
          p_currency_code: string
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: Database["public"]["CompositeTypes"]["pricing_result"]
        SetofOptions: {
          from: "*"
          to: "pricing_result"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      calculate_gold_sell_execution_pricing: {
        Args: {
          p_amount: number
          p_country_code: string
          p_currency_code: string
        }
        Returns: Json
      }
      calculate_gold_sell_pricing: {
        Args: {
          p_amount: number
          p_country_code: string
          p_currency_code: string
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: Database["public"]["CompositeTypes"]["pricing_result"]
        SetofOptions: {
          from: "*"
          to: "pricing_result"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      calculate_gold_transfer_pricing: {
        Args: {
          p_amount: number
          p_country_code: string
          p_currency_code: string
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: Database["public"]["CompositeTypes"]["pricing_result"]
        SetofOptions: {
          from: "*"
          to: "pricing_result"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      calculate_required_collateral: {
        Args: { p_user_id: string }
        Returns: number
      }
      calculate_transaction_pricing: {
        Args: {
          p_country_code: string
          p_currency_code: string
          p_principal: number
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: Database["public"]["CompositeTypes"]["pricing_result"]
        SetofOptions: {
          from: "*"
          to: "pricing_result"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      cash_deposit: {
        Args: {
          p_country_code: string
          p_ip_address?: string
          p_transaction: Json
          p_transaction_state_id: string
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
          p_user_id: string
        }
        Returns: {
          customer_id: string
          device_tokens: string[]
          financial_transaction_id: string
          gross_amount: string
          gross_amount_usd: string
          push_body: string
          push_reference: string
          push_title: string
          receiver_notification_id: string
          reference: string
          success: boolean
        }[]
      }
      cash_transfer: {
        Args: {
          p_country_code: string
          p_fee_payment_method?: string
          p_ip_address?: string
          p_receiver_identifier?: string
          p_sender_id: string
          p_transaction: Json
          p_transaction_state_id: string
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: {
          amount: string
          amount_usd: string
          cash_charges: string
          cash_fee: string
          currency: string
          device_tokens: string[]
          fee_payment_method: string
          financial_transaction_id: string
          loyalty: Json
          original_fee: string
          points_redeemed: number
          push_body: string
          push_reference: string
          push_title: string
          receiver_id: string
          receiver_notification_id: string
          redemption_ledger_id: string
          reference: string
          sender_debit: string
          sender_debit_usd: string
          success: boolean
        }[]
      }
      cash_withdrawal: {
        Args: {
          p_agent_id: string
          p_country_code: string
          p_ip_address?: string
          p_transaction: Json
          p_transaction_state_id: string
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: {
          amount: string
          amount_usd: string
          currency: string
          device_tokens: string[]
          document_no: string
          fee: string
          push_body: string
          push_reference: string
          push_title: string
          sender_debit: string
          sender_debit_usd: string
          success: boolean
          tax: string
          user_notification_id: string
        }[]
      }
      change_my_user_role: {
        Args: { p_identifier: string; p_new_role: string }
        Returns: Json
      }
      claim_country_liquidation_accounting_jobs: {
        Args: { p_batch_size?: number; p_country_code: string }
        Returns: Json
      }
      claim_country_liquidation_blockchain_jobs: {
        Args: { p_batch_size?: number; p_country_code: string }
        Returns: Json
      }
      close_my_fiscal_year: { Args: { p_fiscal_year: number }; Returns: Json }
      complete_gold_buy: {
        Args: {
          p_blockchain_code: string
          p_blockchain_transaction_id: string
          p_country_code: string
          p_ip_address?: string
          p_transaction: Json
          p_transaction_state_id: string
          p_user_id: string
        }
        Returns: {
          device_tokens: string[]
          document_number: string
          explorer_url: string
          push_body: string
          push_reference: string
          push_title: string
          quantity: string
          receiver_notification_id: string
          success: boolean
          total_spent: string
        }[]
      }
      complete_gold_sell: {
        Args: {
          p_blockchain_code: string
          p_blockchain_transaction_id: string
          p_country_code: string
          p_ip_address?: string
          p_seller_id: string
          p_transaction: Json
          p_transaction_state_id: string
        }
        Returns: {
          device_tokens: string[]
          document_number: string
          explorer_url: string
          fee: string
          gross_amount: string
          net_amount: string
          push_body: string
          push_reference: string
          push_title: string
          quantity: string
          receiver_notification_id: string
          success: boolean
          token_document_number: string
        }[]
      }
      complete_gold_transfer: {
        Args: {
          p_blockchain_code?: string
          p_blockchain_transaction_id: string
          p_country_code: string
          p_ip_address?: string
          p_sender_id: string
          p_transaction: Json
          p_transaction_state_id: string
        }
        Returns: {
          amount: string
          device_tokens: string[]
          document_number: string
          explorer_url: string
          fee: string
          push_body: string
          push_reference: string
          push_title: string
          receiver_notification_id: string
          success: boolean
        }[]
      }
      complete_merchant_payment: {
        Args: {
          p_approval: Json
          p_country_code: string
          p_ip_address?: string
          p_payer_id: string
          p_payment_fee_contribution: boolean
          p_transaction: Json
          p_transaction_state_id: string
        }
        Returns: {
          amount: string
          amount_usd: string
          currency_code: string
          device_tokens: string[]
          document_number: string
          financial_transaction_id: string
          payer_debit_amount: string
          payment_fee: string
          payment_fee_contribution: boolean
          payment_fee_usd: string
          push_body: string
          push_reference: string
          push_title: string
          receiver_notification_id: string
          success: boolean
        }[]
      }
      complete_my_token_adjustment_execution: {
        Args: {
          p_adjustment_request_id: string
          p_blockchain_transaction_id: string
          p_ip_address?: string
        }
        Returns: Json
      }
      complete_my_voucher_payment: {
        Args: {
          p_ip_address?: string
          p_transaction: Json
          p_transaction_state_id: string
          p_voucher: Json
        }
        Returns: {
          currency: string
          customer_id: string
          device_tokens: string[]
          fee: string
          gross_amount: string
          gross_amount_usd: string
          notification_id: string
          push_body: string
          push_reference: string
          push_title: string
          reference: string
          success: boolean
          voucher_remaining_balance: string
        }[]
      }
      complete_verified_gold_buy_recovery: {
        Args: {
          p_blockchain_transaction_id: string
          p_executor_id: string
          p_ip_address?: string
          p_verified_context: Json
        }
        Returns: Json
      }
      complete_verified_gold_sell_recovery: {
        Args: {
          p_blockchain_transaction_id: string
          p_executor_id: string
          p_ip_address?: string
          p_verified_context: Json
        }
        Returns: Json
      }
      complete_voucher_payment: {
        Args: {
          p_country_code: string
          p_ip_address?: string
          p_merchant_id: string
          p_transaction: Json
          p_transaction_state_id: string
          p_voucher: Json
        }
        Returns: {
          currency: string
          customer_id: string
          device_tokens: string[]
          fee: string
          gross_amount: string
          gross_amount_usd: string
          notification_id: string
          push_body: string
          push_reference: string
          push_title: string
          reference: string
          success: boolean
          voucher_owner_debit_amount: string
          voucher_owner_debit_amount_usd: string
          voucher_remaining_balance: string
        }[]
      }
      confirm_liquidation_blockchain_transfer: {
        Args: { p_explorer_url?: string; p_queue_id: string; p_tx_hash: string }
        Returns: Json
      }
      create_customer_profile: {
        Args: {
          p_country_code: string
          p_email: string
          p_phone: string
          p_referral_code: string
          p_upliner_code?: string
          p_user_id: string
          p_wallet_address: string
          p_wallet_index: number
        }
        Returns: {
          city: string | null
          country_code: string
          created_at: string
          dob: string | null
          email: string | null
          first_name: string | null
          gender: Database["public"]["Enums"]["GenderType"] | null
          id: string
          middle_name: string | null
          nationality: string | null
          phone: string | null
          preferred_language: string
          province_state: string | null
          referral_code: string
          residential_address: string | null
          role_id: string
          status: Database["public"]["Enums"]["UserStatus"]
          surname: string | null
          updated_at: string
          upliner: string | null
          wallet_address: string
          wallet_index: number
        }
        SetofOptions: {
          from: "*"
          to: "users"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_my_agent_commission_settlement_batch: {
        Args: {
          p_currency_code: string
          p_end_date: string
          p_start_date: string
        }
        Returns: Json
      }
      create_my_cash_deposit_state: {
        Args: { p_sender_approval: Json; p_transaction: Json }
        Returns: string
      }
      create_my_cash_withdrawal_state: {
        Args: { p_sender_approval: Json; p_transaction: Json }
        Returns: string
      }
      create_my_credit_agent_cash_deposit_state: {
        Args: { p_sender_approval: Json; p_transaction: Json }
        Returns: string
      }
      create_my_credit_agent_cash_settlement_state: {
        Args: { p_sender_approval: Json; p_transaction: Json }
        Returns: string
      }
      create_my_credit_agent_cash_withdrawal_state: {
        Args: { p_sender_approval: Json; p_transaction: Json }
        Returns: string
      }
      create_my_gold_buy_state: {
        Args: { p_blockchain_code: string; p_transaction: Json }
        Returns: string
      }
      create_my_gold_sell_state: {
        Args: { p_blockchain_code: string; p_transaction: Json }
        Returns: string
      }
      create_my_gold_transfer_state: {
        Args: { p_blockchain_code: string; p_transaction: Json }
        Returns: string
      }
      create_my_government_tax_settlement_batch: {
        Args: {
          p_currency_code: string
          p_end_date: string
          p_start_date: string
        }
        Returns: Json
      }
      create_my_merchant_payment_state:
        | { Args: { p_approval: Json; p_transaction: Json }; Returns: string }
        | {
            Args: {
              p_approval: Json
              p_payment_fee_contribution: boolean
              p_transaction: Json
            }
            Returns: string
          }
      create_my_transaction_state: {
        Args: {
          p_receiver_identifier?: string
          p_transaction: Json
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: string
      }
      create_my_voucher_payment_state: {
        Args: { p_transaction: Json; p_voucher: Json }
        Returns: string
      }
      create_notification_message: {
        Args: {
          p_amount: number
          p_audience: Database["public"]["Enums"]["NotificationAudience"]
          p_country_code: string
          p_currency: string
          p_fee?: number
          p_gross_amount?: number
          p_quantity?: number
          p_receiver?: string
          p_reference: string
          p_sender?: string
          p_tax?: number
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: Database["public"]["CompositeTypes"]["notification_message"]
        SetofOptions: {
          from: "*"
          to: "notification_message"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      create_weekly_agent_commission_batch: {
        Args: {
          p_country_code: string
          p_currency_code: string
          p_week_start: string
        }
        Returns: Json
      }
      credit_agent_cash_deposit: {
        Args: {
          p_country_code: string
          p_ip_address?: string
          p_transaction: Json
          p_transaction_state_id: string
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
          p_user_id: string
        }
        Returns: {
          customer_id: string
          device_tokens: string[]
          financial_transaction_id: string
          gross_amount: string
          gross_amount_usd: string
          push_body: string
          push_reference: string
          push_title: string
          receiver_notification_id: string
          reference: string
          success: boolean
        }[]
      }
      credit_agent_cash_deposit_posting: {
        Args: {
          p_country_code: string
          p_ip_address?: string
          p_transaction: Json
          p_transaction_state_id: string
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
          p_user_id: string
        }
        Returns: {
          customer_id: string
          device_tokens: string[]
          gross_amount: string
          push_body: string
          push_reference: string
          push_title: string
          receiver_notification_id: string
          reference: string
          success: boolean
        }[]
      }
      credit_agent_cash_settlement: {
        Args: {
          p_country_code: string
          p_ip_address?: string
          p_merchant_id: string
          p_transaction: Json
          p_transaction_state_id: string
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: {
          accounts_id: string
          cash_holding_after: string
          cash_holding_before: string
          currency_code: string
          device_tokens: string[]
          document_number: string
          merchant_id: string
          merchant_notification_id: string
          push_body: string
          push_reference: string
          push_title: string
          reference: string
          settled_amount: string
          success: boolean
        }[]
      }
      credit_agent_cash_withdrawal: {
        Args: {
          p_agent_id: string
          p_country_code: string
          p_ip_address?: string
          p_transaction: Json
          p_transaction_state_id: string
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: {
          amount: string
          amount_usd: string
          currency: string
          device_tokens: string[]
          document_no: string
          fee: string
          holding_used: string
          push_body: string
          push_reference: string
          push_title: string
          receivable_used: string
          sender_debit: string
          sender_debit_usd: string
          success: boolean
          tax: string
          user_notification_id: string
        }[]
      }
      detect_unhealthy_loan_positions: {
        Args: { p_country_code: string; p_gold_price_per_gram: number }
        Returns: Json
      }
      enforce_transaction_limit: {
        Args: {
          p_amount: number
          p_country_code: string
          p_currency_code: string
          p_fiscal_year: number
          p_period: number
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
          p_user_id: string
        }
        Returns: undefined
      }
      evaluate_financial_badges: {
        Args: {
          p_country_code: string
          p_fiscal_year: number
          p_period: number
          p_user_id: string
        }
        Returns: {
          achieved_value_usd: number
          badge_code: string
          badge_id: string
          badge_name: string
          metric: Database["public"]["Enums"]["financial_badge_metric"]
          newly_awarded: boolean
        }[]
      }
      evaluate_user_badges: {
        Args: { p_event_id?: string; p_user_id: string }
        Returns: Json
      }
      execute_additional_collateral: {
        Args: {
          p_reference: string
          p_requested_collateral: string
          p_token_balance: string
          p_user_id: string
        }
        Returns: {
          collateral_added: string
          collateral_required: boolean
          loans_adjusted: number
          new_locked_collateral: string
          previous_locked_collateral: string
          remaining_required_collateral: string
          requested_collateral: string
          success: boolean
          unused_collateral: string
        }[]
      }
      execute_loan_disbursement: {
        Args: {
          p_currency_code?: string
          p_ip_address?: string
          p_reference: string
          p_requested_amount: string
          p_token_balance: string
          p_user_id: string
        }
        Returns: {
          collateral_locked: string
          country_code: string
          currency_code: string
          customer_id: string
          device_tokens: string[]
          document_number: string
          initiation_fee: string
          loan_id: string
          net_disbursed: string
          notification_id: string
          principal_amount: string
          push_body: string
          push_reference: string
          push_title: string
          success: boolean
        }[]
      }
      execute_my_additional_collateral: {
        Args: {
          p_reference: string
          p_requested_collateral: string
          p_token_balance: string
        }
        Returns: {
          collateral_added: string
          collateral_required: boolean
          loans_adjusted: number
          new_locked_collateral: string
          previous_locked_collateral: string
          remaining_required_collateral: string
          requested_collateral: string
          success: boolean
          unused_collateral: string
        }[]
      }
      execute_my_agent_commission_settlement_batch: {
        Args: { p_batch_id: string; p_ip_address?: string }
        Returns: Json
      }
      execute_my_agent_funding: {
        Args: {
          p_agent_identifier?: string
          p_amount?: number
          p_currency_code?: string
          p_document_number?: string
          p_ip_address?: string
          p_reference?: string
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: Json
      }
      execute_my_credit_agent_cash_deposit: {
        Args: {
          p_amount: number
          p_currency_code: string
          p_customer_identifier: string
          p_ip_address?: string
          p_reference: string
        }
        Returns: Json
      }
      execute_my_credit_agent_funding: {
        Args: {
          p_agent_identifier: string
          p_amount: number
          p_currency_code: string
          p_ip_address?: string
          p_reference: string
        }
        Returns: Json
      }
      execute_my_customer_direct_deposit: {
        Args: {
          p_amount: number
          p_currency_code: string
          p_identifier: string
          p_ip_address?: string
          p_reference: string
        }
        Returns: Json
      }
      execute_my_external_funding:
        | {
            Args: {
              p_amount?: number
              p_currency_code?: string
              p_ip_address?: string
              p_original_document_number?: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_amount?: number
              p_currency_code?: string
              p_document_number?: string
              p_ip_address?: string
              p_transaction_type: Database["public"]["Enums"]["TransactionType"]
            }
            Returns: Json
          }
      execute_my_gold_inventory_purchase: {
        Args: {
          p_bar_serial_number?: string
          p_currency_code?: string
          p_custodian_name?: string
          p_document_number?: string
          p_ip_address?: string
          p_price_per_gram?: number
          p_quantity_grams?: number
          p_supplier_name?: string
          p_token_total_supply: number
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: Json
      }
      execute_my_government_tax_settlement_batch: {
        Args: { p_batch_id: string; p_ip_address?: string }
        Returns: Json
      }
      execute_my_loan_disbursement: {
        Args: {
          p_currency_code?: string
          p_ip_address?: string
          p_reference: string
          p_requested_amount: string
          p_token_balance: string
        }
        Returns: {
          collateral_locked: string
          country_code: string
          currency_code: string
          customer_id: string
          device_tokens: string[]
          document_number: string
          initiation_fee: string
          loan_id: string
          net_disbursed: string
          notification_id: string
          principal_amount: string
          push_body: string
          push_reference: string
          push_title: string
          success: boolean
        }[]
      }
      execute_my_loan_repayment: {
        Args: {
          p_amount: string
          p_currency_code?: string
          p_ip_address?: string
          p_reference: string
        }
        Returns: {
          collateral_unlocked: string
          country_code: string
          currency_code: string
          customer_id: string
          document_number: string
          interest_paid: string
          loans_closed: number
          payment_applied: string
          principal_paid: string
          success: boolean
          unused_payment: string
          wallet_debit: string
        }[]
      }
      execute_my_treasury_funding: {
        Args: {
          p_amount?: number
          p_currency_code?: string
          p_document_number?: string
          p_ip_address?: string
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: Json
      }
      extract_component_totals: {
        Args: {
          p_components: Database["public"]["CompositeTypes"]["posting_component"][]
          p_reverse?: boolean
        }
        Returns: Database["public"]["CompositeTypes"]["component_totals"]
        SetofOptions: {
          from: "*"
          to: "component_totals"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fail_liquidation_accounting_job: {
        Args: { p_error_message: string; p_job_id: string }
        Returns: Json
      }
      fail_liquidation_blockchain_transfer: {
        Args: {
          p_error_message: string
          p_queue_id: string
          p_tx_hash?: string
        }
        Returns: Json
      }
      fetch_active_operational_countries: {
        Args: never
        Returns: {
          country_code: string
        }[]
      }
      fetch_active_supported_blockchain: {
        Args: { p_blockchain_code: string }
        Returns: {
          chain_id: number
          code: string
          contract_address: string
          explorer_url: string
          native_currency_code: string
          rpc_url: string
        }[]
      }
      fetch_active_supported_blockchains: {
        Args: never
        Returns: {
          chain_id: number
          code: string
          contract_address: string
          native_currency_code: string
          rpc_url: string
        }[]
      }
      fetch_active_user_by_id: {
        Args: { p_user_id: string }
        Returns: {
          city: string | null
          country_code: string
          created_at: string
          dob: string | null
          email: string | null
          first_name: string | null
          gender: Database["public"]["Enums"]["GenderType"] | null
          id: string
          middle_name: string | null
          nationality: string | null
          phone: string | null
          preferred_language: string
          province_state: string | null
          referral_code: string
          residential_address: string | null
          role_id: string
          status: Database["public"]["Enums"]["UserStatus"]
          surname: string | null
          updated_at: string
          upliner: string | null
          wallet_address: string
          wallet_index: number
        }[]
        SetofOptions: {
          from: "*"
          to: "users"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      fetch_agent_commission_rate: {
        Args: {
          p_country_code: string
          p_currency_code: string
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: number
      }
      fetch_all_transaction_configs: {
        Args: { p_country_code: string; p_currency_code?: string }
        Returns: {
          config_key: string
          currency_code: string
          fixed_amount: number
          max_amount: number
          min_amount: number
          percentage: number
        }[]
      }
      fetch_country_calling_code: {
        Args: { p_country_code: string }
        Returns: string
      }
      fetch_country_treasury: {
        Args: { p_country_code: string }
        Returns: {
          city: string | null
          country_code: string
          created_at: string
          dob: string | null
          email: string | null
          first_name: string | null
          gender: Database["public"]["Enums"]["GenderType"] | null
          id: string
          middle_name: string | null
          nationality: string | null
          phone: string | null
          preferred_language: string
          province_state: string | null
          referral_code: string
          residential_address: string | null
          role_id: string
          status: Database["public"]["Enums"]["UserStatus"]
          surname: string | null
          updated_at: string
          upliner: string | null
          wallet_address: string
          wallet_index: number
        }
        SetofOptions: {
          from: "*"
          to: "users"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fetch_device_tokens: {
        Args: { p_country_code: string; p_user_id: string }
        Returns: string[]
      }
      fetch_fiat_price_update_currencies: {
        Args: never
        Returns: {
          currency_code: string
          rate_api: string
        }[]
      }
      fetch_financial_statement_gl_entries: {
        Args: {
          p_currency_code: string
          p_end_date: string
          p_gl: string
          p_page?: number
          p_page_size?: number
          p_start_date: string
        }
        Returns: Json
      }
      fetch_fiscal_period: {
        Args: { p_country_code: string; p_date?: string }
        Returns: {
          fiscal_year: number
          period: number
          period_name: string
        }[]
      }
      fetch_gl_mappings: {
        Args: {
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: {
          component_type: Database["public"]["Enums"]["ComponentType"]
          created_at: string
          created_by: string
          credit_gl: string
          debit_gl: string
          id: string
          is_active: boolean
          transaction_type: Database["public"]["Enums"]["TransactionType"]
          updated_at: string
          updated_by: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "transaction_gl_mapping"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      fetch_gold_price: { Args: never; Returns: number }
      fetch_gold_rate_api: {
        Args: never
        Returns: {
          rate_api: string
        }[]
      }
      fetch_gold_sell_execution_context: {
        Args: { p_transaction_state_id: string }
        Returns: Json
      }
      fetch_government_tax_rate: {
        Args: {
          p_country_code: string
          p_currency_code: string
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: number
      }
      fetch_incomplete_blockchain_transactions: {
        Args: { p_page?: number; p_page_size?: number }
        Returns: Json
      }
      fetch_kyc_review_queue: {
        Args: { p_country_code?: string; p_page?: number; p_page_size?: number }
        Returns: Json
      }
      fetch_liquidation_blockchain_config: {
        Args: { p_queue_id: string }
        Returns: {
          chain_id: number
          code: string
          contract_address: string
          explorer_url: string
          native_currency_code: string
          rpc_url: string
          treasury_wallet_address: string
        }[]
      }
      fetch_liquidation_reconciliation_context: {
        Args: { p_job_id: string }
        Returns: Json
      }
      fetch_merchant_commission_rate: {
        Args: {
          p_country_code: string
          p_currency_code: string
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: number
      }
      fetch_my_active_loan_detail:
        | { Args: { p_loan_id: string }; Returns: Json }
        | {
            Args: { p_loan_id: string; p_page?: number; p_page_size?: number }
            Returns: Json
          }
      fetch_my_active_loans: { Args: never; Returns: Json }
      fetch_my_additional_collateral_context: {
        Args: never
        Returns: {
          country_code: string
          user_id: string
          user_wallet_address: string
        }[]
      }
      fetch_my_agent_commission_batches: {
        Args: { p_status: Database["public"]["Enums"]["SettlementStatus"] }
        Returns: Json
      }
      fetch_my_agent_commission_settlement_batches: {
        Args: { p_statuses: Database["public"]["Enums"]["SettlementStatus"][] }
        Returns: Json
      }
      fetch_my_agent_commission_settlement_items: {
        Args: { p_batch_id: string; p_page?: number; p_page_size?: number }
        Returns: Json
      }
      fetch_my_agent_commission_summary: { Args: never; Returns: Json }
      fetch_my_agent_dashboard_context: {
        Args: never
        Returns: {
          wallet_address: string
        }[]
      }
      fetch_my_balance_sheet: {
        Args: { p_as_of_date: string; p_currency_code?: string }
        Returns: Json
      }
      fetch_my_blockchain_recovery_context: {
        Args: { p_blockchain_transaction_id: string }
        Returns: Json
      }
      fetch_my_cash_deposit_context: {
        Args: { p_provider_id: string; p_v: string }
        Returns: {
          country_code: string
          provider_country_code: string
          provider_id: string
          provider_wallet_address: string
          user_id: string
          user_wallet_address: string
          version_time: number
        }[]
      }
      fetch_my_cash_transfer_context: {
        Args: { p_v: string }
        Returns: {
          country_code: string
          sender_id: string
          version_time: number
          wallet_address: string
        }[]
      }
      fetch_my_cash_transfer_fee_configuration: { Args: never; Returns: Json }
      fetch_my_cash_withdrawal_context: {
        Args: { p_user_id: string; p_v: string }
        Returns: {
          agent_id: string
          agent_wallet_address: string
          country_code: string
          user_country_code: string
          user_id: string
          user_wallet_address: string
          version_time: number
        }[]
      }
      fetch_my_credit_agent_balances:
        | { Args: never; Returns: Json }
        | { Args: { p_page?: number; p_page_size?: number }; Returns: Json }
      fetch_my_credit_agent_cash_settlement_context: {
        Args: { p_accounts_id: string; p_currency_code: string; p_v: string }
        Returns: {
          accounts_country_code: string
          accounts_id: string
          accounts_wallet_address: string
          merchant_country_code: string
          merchant_id: string
          merchant_wallet_address: string
          treasury_id: string
          version_time: number
        }[]
      }
      fetch_my_credit_agent_drilldown: {
        Args: {
          p_currency_code: string
          p_merchant_id: string
          p_page?: number
          p_page_size?: number
        }
        Returns: Json
      }
      fetch_my_current_gl_balances: { Args: never; Returns: Json }
      fetch_my_current_government_tax: {
        Args: {
          p_as_of?: string
          p_currency_code?: string
          p_page?: number
          p_page_size?: number
        }
        Returns: Json
      }
      fetch_my_current_period_agent_commissions: {
        Args: {
          p_as_of?: string
          p_currency_code?: string
          p_page?: number
          p_page_size?: number
        }
        Returns: Json
      }
      fetch_my_current_token_gl_balance: { Args: never; Returns: Json }
      fetch_my_customer_dashboard_context: {
        Args: never
        Returns: {
          wallet_address: string
        }[]
      }
      fetch_my_express_tap_limits: {
        Args: never
        Returns: {
          currency_code: string
          express_tap_limit: number
          is_active: boolean
        }[]
      }
      fetch_my_financial_document: {
        Args: { p_document_number: string }
        Returns: Json
      }
      fetch_my_fiscal_periods: { Args: never; Returns: Json }
      fetch_my_gamification_notifications: {
        Args: { p_limit?: number }
        Returns: Json
      }
      fetch_my_gl_period_entries: {
        Args: {
          p_currency_code: string
          p_fiscal_year: number
          p_gl_account_code: string
          p_page?: number
          p_page_size?: number
          p_period: number
        }
        Returns: Json
      }
      fetch_my_gl_periodic_balances: {
        Args: { p_currency_code?: string; p_gl_account_code: string }
        Returns: Json
      }
      fetch_my_gold_buy_context: {
        Args: { p_blockchain_code: string; p_v: string }
        Returns: {
          blockchain_code: string
          country_code: string
          user_id: string
          version_time: number
          wallet_address: string
          wallet_index: number
        }[]
      }
      fetch_my_gold_sell_context: {
        Args: { p_blockchain_code: string; p_v: string }
        Returns: {
          blockchain_code: string
          country_code: string
          seller_id: string
          version_time: number
          wallet_address: string
          wallet_index: number
        }[]
      }
      fetch_my_gold_transfer_context: {
        Args: { p_v: string }
        Returns: {
          country_code: string
          sender_id: string
          version_time: number
          wallet_address: string
          wallet_index: number
        }[]
      }
      fetch_my_government_tax_settlement_batches: {
        Args: { p_statuses: Database["public"]["Enums"]["SettlementStatus"][] }
        Returns: Json
      }
      fetch_my_government_tax_settlement_items: {
        Args: { p_batch_id: string; p_page?: number; p_page_size?: number }
        Returns: Json
      }
      fetch_my_incomplete_liquidation_jobs: {
        Args: { p_page?: number; p_page_size?: number }
        Returns: Json
      }
      fetch_my_last_agent_commission_settlement: { Args: never; Returns: Json }
      fetch_my_last_government_tax_settlement: { Args: never; Returns: Json }
      fetch_my_last_loan_interest_accrual: {
        Args: never
        Returns: {
          last_accrual_run: string
        }[]
      }
      fetch_my_liquidated_loans_by_date: {
        Args: {
          p_liquidation_date: string
          p_page?: number
          p_page_size?: number
        }
        Returns: Json
      }
      fetch_my_loan_preview_context: {
        Args: never
        Returns: {
          country_code: string
          wallet_address: string
        }[]
      }
      fetch_my_loan_repayment_context: {
        Args: never
        Returns: {
          country_code: string
          user_id: string
        }[]
      }
      fetch_my_loyalty_badges: { Args: never; Returns: Json }
      fetch_my_loyalty_ledger: {
        Args: { p_page?: number; p_page_size?: number }
        Returns: Json
      }
      fetch_my_loyalty_summary: { Args: never; Returns: Json }
      fetch_my_manual_review_liquidation_job: {
        Args: { p_job_id: string }
        Returns: Json
      }
      fetch_my_manual_review_liquidation_jobs: {
        Args: { p_page?: number; p_page_size?: number }
        Returns: Json
      }
      fetch_my_merchant_payment_context: {
        Args: { p_merchant_id: string; p_v: string }
        Returns: {
          country_code: string
          merchant_id: string
          merchant_wallet_address: string
          payer_id: string
          payer_wallet_address: string
          version_time: number
        }[]
      }
      fetch_my_multi_wallet_context: {
        Args: never
        Returns: {
          wallet_address: string
        }[]
      }
      fetch_my_profit_and_loss: {
        Args: {
          p_currency_code?: string
          p_end_date: string
          p_start_date: string
        }
        Returns: Json
      }
      fetch_my_recent_financial_transactions: {
        Args: {
          p_currency_code?: string
          p_end_date?: string
          p_page?: number
          p_page_size?: number
          p_start_date?: string
        }
        Returns: Json
      }
      fetch_my_transaction_configs: {
        Args: never
        Returns: {
          config_key: string
          currency_code: string
          fixed_amount: number
          max_amount: number
          min_amount: number
          percentage: number
        }[]
      }
      fetch_my_treasury_dashboard_context: {
        Args: never
        Returns: {
          country_code: string
          user_id: string
          wallet_address: string
        }[]
      }
      fetch_my_trial_balance: {
        Args: {
          p_currency_code?: string
          p_end_date?: string
          p_start_date?: string
        }
        Returns: Json
      }
      fetch_my_user_contact_context: {
        Args: { p_country_code: string }
        Returns: {
          calling_code: string
          country_code: string
          country_name: string
          current_email: string
          current_phone: string
          user_id: string
        }[]
      }
      fetch_my_user_details: { Args: never; Returns: Json }
      fetch_my_vendor_dashboard_context: {
        Args: never
        Returns: {
          wallet_address: string
        }[]
      }
      fetch_my_voucher_payment_context: {
        Args: { p_v: string; p_voucher_owner_id: string }
        Returns: {
          country_code: string
          merchant_id: string
          merchant_wallet_address: string
          version_time: number
          voucher_owner_wallet_address: string
        }[]
      }
      fetch_opening_wallet_snapshot: {
        Args: {
          p_blockchain_code?: string
          p_currency_code: string
          p_fiscal_year: number
          p_period: number
          p_user_id: string
          p_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
        }
        Returns: {
          closing_balance: number
          credit: number
          currency_code: string
          debit: number
          fiscal_year: number
          opening_balance: number
          period: number
          user_id: string
          wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
        }[]
      }
      fetch_operational_countries: {
        Args: never
        Returns: {
          country_code: string
          name: string
        }[]
      }
      fetch_password_reset_context: {
        Args: { p_identifier: string }
        Returns: {
          email: string
          identifier_type: string
          phone: string
        }[]
      }
      fetch_public_gold_price: { Args: never; Returns: number }
      fetch_spread_by_direction: {
        Args: {
          p_asset: Database["public"]["Enums"]["AssetType"]
          p_direction: Database["public"]["Enums"]["SpreadDirection"]
        }
        Returns: {
          config_key: string
          currency_code: string
          fixed_amount: number
          max_amount: number
          min_amount: number
          percentage: number
        }[]
      }
      fetch_token_adjustments_by_status: {
        Args: { p_status: string }
        Returns: {
          adjustment_type: Database["public"]["Enums"]["TokenAdjustmentType"]
          available_gold: number
          description: string
          document_number: string
          id: string
          quantity: number
          status: Database["public"]["Enums"]["AdjustmentStatus"]
          uom: Database["public"]["Enums"]["Uom"]
        }[]
      }
      fetch_token_role_grant_config: {
        Args: { p_blockchain_code: string }
        Returns: Json
      }
      fetch_transaction_doc_num_prefix: {
        Args: {
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: string
      }
      fetch_transaction_type_wallet_owner: {
        Args: {
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: {
          audit_action_type: Database["public"]["Enums"]["AuditActionType"]
          id: string
          receiver_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
          sender_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        SetofOptions: {
          from: "*"
          to: "transaction_type_wallet_owner"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fetch_user_by_email_or_phone: {
        Args: { p_email_or_phone: string }
        Returns: {
          city: string | null
          country_code: string
          created_at: string
          dob: string | null
          email: string | null
          first_name: string | null
          gender: Database["public"]["Enums"]["GenderType"] | null
          id: string
          middle_name: string | null
          nationality: string | null
          phone: string | null
          preferred_language: string
          province_state: string | null
          referral_code: string
          residential_address: string | null
          role_id: string
          status: Database["public"]["Enums"]["UserStatus"]
          surname: string | null
          updated_at: string
          upliner: string | null
          wallet_address: string
          wallet_index: number
        }
        SetofOptions: {
          from: "*"
          to: "users"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fetch_user_by_id: {
        Args: { p_user_id: string }
        Returns: {
          city: string | null
          country_code: string
          created_at: string
          dob: string | null
          email: string | null
          first_name: string | null
          gender: Database["public"]["Enums"]["GenderType"] | null
          id: string
          middle_name: string | null
          nationality: string | null
          phone: string | null
          preferred_language: string
          province_state: string | null
          referral_code: string
          residential_address: string | null
          role_id: string
          status: Database["public"]["Enums"]["UserStatus"]
          surname: string | null
          updated_at: string
          upliner: string | null
          wallet_address: string
          wallet_index: number
        }[]
        SetofOptions: {
          from: "*"
          to: "users"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      fetch_user_kyc_review: { Args: { p_user_id: string }; Returns: Json }
      fetch_voucher_used_amount: {
        Args: { p_voucher_reference: string }
        Returns: number
      }
      fetch_wallet: {
        Args: {
          p_blockchain_code?: string
          p_currency_code: string
          p_user_id: string
          p_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
        }
        Returns: {
          balance: number
          blockchain_code: string | null
          country_code: string
          created_at: string
          currency_code: string
          id: string
          is_active: boolean
          owner_type: Database["public"]["Enums"]["WalletOwnerType"]
          updated_at: string
          user_id: string
        }
        SetofOptions: {
          from: "*"
          to: "wallet"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      finalise_liquidation_accounting_job: {
        Args: { p_job_id: string }
        Returns: Json
      }
      generate_document_number: {
        Args: {
          p_country_code: string
          p_fiscal_year: number
          p_period: number
          p_prefix: string
        }
        Returns: string
      }
      get_all_transaction_v: {
        Args: never
        Returns: {
          time: number
          v: string
        }[]
      }
      get_base_transaction_type: {
        Args: {
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: Database["public"]["Enums"]["TransactionType"]
      }
      get_last_wallet_transactions: {
        Args: {
          p_currency_code?: string
          p_end_date: string
          p_page?: number
          p_page_size?: number
          p_start_date: string
          p_user_id: string
        }
        Returns: Json
      }
      get_multi_wallet_balances: { Args: { p_user_id: string }; Returns: Json }
      get_my_financial_badges: { Args: never; Returns: Json }
      get_my_financial_periods: { Args: never; Returns: Json }
      get_my_financial_summary: { Args: never; Returns: Json }
      get_my_last_wallet_transactions: {
        Args: {
          p_currency_code?: string
          p_end_date: string
          p_page?: number
          p_page_size?: number
          p_start_date: string
        }
        Returns: Json
      }
      get_my_multi_wallet_balances: { Args: never; Returns: Json }
      get_my_wallet_balance_snapshot: {
        Args: {
          p_blockchain_code?: string
          p_currency_code: string
          p_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
        }
        Returns: Json
      }
      get_my_wallet_balances: { Args: never; Returns: Json }
      get_my_wallet_period_entries: {
        Args: {
          p_blockchain_code?: string
          p_currency_code: string
          p_fiscal_year: number
          p_page?: number
          p_page_size?: number
          p_period: number
          p_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
        }
        Returns: Json
      }
      get_next_wallet_index: { Args: never; Returns: number }
      get_transaction_v: { Args: { p_v: string }; Returns: number }
      get_wallet_balance_snapshot: {
        Args: {
          p_blockchain_code?: string
          p_country_code: string
          p_currency_code: string
          p_user_id: string
          p_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
        }
        Returns: Json
      }
      get_wallet_balances:
        | { Args: never; Returns: Json }
        | { Args: { p_user_id: string }; Returns: Json }
      get_wallet_period_entries: {
        Args: {
          p_blockchain_code?: string
          p_currency_code: string
          p_fiscal_year: number
          p_page?: number
          p_page_size?: number
          p_period: number
          p_user_id: string
          p_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
        }
        Returns: Json
      }
      has_role:
        | {
            Args: { p_allowed_roles: Database["public"]["Enums"]["Role"][] }
            Returns: {
              error: true
            } & "Could not choose the best candidate function between: public.has_role(p_allowed_roles => _text), public.has_role(p_allowed_roles => _Role). Try renaming the parameters or the function itself in the database so function overloading can be resolved"
          }
        | {
            Args: { p_allowed_roles: string[] }
            Returns: {
              error: true
            } & "Could not choose the best candidate function between: public.has_role(p_allowed_roles => _text), public.has_role(p_allowed_roles => _Role). Try renaming the parameters or the function itself in the database so function overloading can be resolved"
          }
      is_gold_sub_transaction: {
        Args: {
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: boolean
      }
      is_gold_transaction: {
        Args: {
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: boolean
      }
      is_self_balancing_component: {
        Args: { p_component_type: Database["public"]["Enums"]["ComponentType"] }
        Returns: boolean
      }
      ngoda_add_check_constraint: {
        Args: { p_check_sql: string; p_constraint: string; p_table: string }
        Returns: undefined
      }
      open_my_next_fiscal_year: { Args: never; Returns: Json }
      post_credit_agent_entry: {
        Args: {
          p_created_by: string
          p_credit_agent_account_id: string
          p_credit_cash_holding: number
          p_credit_receivable: number
          p_debit_cash_holding: number
          p_debit_receivable: number
          p_document_number: string
          p_fiscal_year: number
          p_period: number
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: {
          cash_holding_balance_after: number
          cash_holding_balance_before: number
          country_code: string
          created_at: string
          created_by: string
          credit_agent_account_id: string
          credit_cash_holding: number
          credit_receivable: number
          currency_code: string
          debit_cash_holding: number
          debit_receivable: number
          document_number: string
          fiscal_year: number
          id: string
          merchant_id: string
          period: number
          receivable_balance_after: number
          receivable_balance_before: number
          transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        SetofOptions: {
          from: "*"
          to: "credit_agent_entry"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      post_financial_entries: {
        Args: {
          p_components: Database["public"]["CompositeTypes"]["posting_component"][]
          p_country_code: string
          p_created_by: string
          p_currency_code: string
          p_deposit_type?: Database["public"]["Enums"]["CustomerDepositType"]
          p_document_number: string
          p_fiscal_year: number
          p_mappings: Database["public"]["Tables"]["transaction_gl_mapping"]["Row"][]
          p_period: number
          p_reference?: string
          p_transaction_id: number
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: {
          count: number
          total_credit: number
          total_debit: number
        }[]
      }
      post_wallet_entries: {
        Args: {
          p_audit_action_type: Database["public"]["Enums"]["AuditActionType"]
          p_blockchain_code?: string
          p_country_code: string
          p_credit_amount: number
          p_currency_code: string
          p_debit_amount: number
          p_document_number: string
          p_fee_amount?: number
          p_fiscal_year: number
          p_ip_address?: string
          p_period: number
          p_receiver_id: string
          p_receiver_notification?: Database["public"]["CompositeTypes"]["notification_message"]
          p_receiver_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
          p_reference: string
          p_sender_id: string
          p_sender_notification?: Database["public"]["CompositeTypes"]["notification_message"]
          p_sender_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
          p_treasury_id?: string
        }
        Returns: {
          receiver_notification_id: string
          wallet_entry_count: number
        }[]
      }
      prepare_country_liquidation_blockchain_jobs: {
        Args: { p_batch_size?: number; p_country_code: string }
        Returns: Json
      }
      prepare_gold_buy: {
        Args: {
          p_blockchain_code: string
          p_country_code: string
          p_transaction: Json
          p_transaction_state_id: string
          p_user_id: string
        }
        Returns: {
          blockchain_code: string
          country_code: string
          document_prefix: string
          fiscal_year: number
          gold_price: string
          gross_amount: string
          gross_token_quantity: string
          input_amount: string
          input_currency: string
          period: number
          spread: string
          token_fee: string
          token_quantity: string
          treasury_id: string
          treasury_wallet_address: string
          treasury_wallet_index: number
          user_id: string
          user_wallet_address: string
        }[]
      }
      prepare_gold_sell: {
        Args: {
          p_blockchain_code: string
          p_country_code: string
          p_seller_id: string
          p_transaction: Json
          p_transaction_state_id: string
        }
        Returns: {
          blockchain_code: string
          country_code: string
          document_prefix: string
          fiat_fee: string
          fiscal_year: number
          gold_price: string
          government_tax: string
          gross_amount: string
          input_amount: string
          input_currency: string
          net_amount: string
          period: number
          sell_components: Database["public"]["CompositeTypes"]["posting_component"][]
          sell_mappings: Database["public"]["Tables"]["transaction_gl_mapping"]["Row"][]
          seller_id: string
          seller_wallet_address: string
          seller_wallet_index: number
          token_components: Database["public"]["CompositeTypes"]["posting_component"][]
          token_fee_equivalent: string
          token_mappings: Database["public"]["Tables"]["transaction_gl_mapping"]["Row"][]
          token_quantity: string
          trading_spread: string
          treasury_id: string
          treasury_wallet_address: string
        }[]
      }
      prepare_gold_transfer: {
        Args: {
          p_blockchain_code: string
          p_country_code: string
          p_sender_id: string
          p_transaction: Json
          p_transaction_state_id: string
        }
        Returns: {
          amount: string
          blockchain_code: string
          components: Database["public"]["CompositeTypes"]["posting_component"][]
          country_code: string
          document_prefix: string
          fee: string
          fiscal_year: number
          mappings: Database["public"]["Tables"]["transaction_gl_mapping"]["Row"][]
          period: number
          receiver_id: string
          receiver_wallet_address: string
          sender_id: string
          sender_wallet_address: string
          sender_wallet_index: number
          total_amount: string
          treasury_id: string
          treasury_wallet_address: string
        }[]
      }
      prepare_merchant_payment: {
        Args: {
          p_approval: Json
          p_country_code: string
          p_payer_id: string
          p_payment_fee_contribution: boolean
          p_transaction: Json
          p_transaction_state_id: string
        }
        Returns: {
          amount: string
          commission_amount: string
          commission_rate: string
          components: Database["public"]["CompositeTypes"]["posting_component"][]
          country_code: string
          currency_code: string
          document_prefix: string
          fiscal_year: number
          mappings: Database["public"]["Tables"]["transaction_gl_mapping"]["Row"][]
          merchant_credit_amount: string
          merchant_id: string
          merchant_wallet_address: string
          other_amount: string
          payer_debit_amount: string
          payer_id: string
          payer_wallet_address: string
          payment_fee: string
          period: number
          treasury_id: string
        }[]
      }
      prepare_my_token_adjustment_execution: {
        Args: { p_adjustment_request_id: string; p_blockchain_code: string }
        Returns: Json
      }
      preview_loan_for_user: {
        Args: {
          p_currency_code?: string
          p_requested_amount: string
          p_token_balance: string
          p_user_id: string
        }
        Returns: Json
      }
      preview_my_loan: {
        Args: {
          p_currency_code?: string
          p_requested_amount: string
          p_token_balance: string
        }
        Returns: Json
      }
      process_my_incomplete_blockchain_transaction: {
        Args: { p_blockchain_transaction_id: string; p_ip_address?: string }
        Returns: Json
      }
      record_financial_activity: {
        Args: {
          p_activity_type: Database["public"]["Enums"]["financial_activity_type"]
          p_amount?: number
          p_amount_usd?: number
          p_cash_amount?: number
          p_cash_amount_usd?: number
          p_country_code: string
          p_currency_code: string
          p_gold_quantity?: number
          p_interest_amount?: number
          p_interest_amount_usd?: number
          p_investment_cost_usd?: number
          p_principal_amount?: number
          p_principal_amount_usd?: number
          p_reference: string
          p_transaction_type: string
          p_user_id: string
        }
        Returns: {
          borrowing_percentage: number
          cash_in_amount: number
          cash_in_amount_usd: number
          closing_gold_quantity: number
          closing_investment_usd: number
          closing_loan_balance: number
          closing_loan_balance_usd: number
          closing_savings: number
          closing_savings_usd: number
          country_code: string
          created_at: string
          currency_code: string
          deposit_amount: number
          deposit_amount_usd: number
          fiscal_year: number
          gold_purchased: number
          gold_sold: number
          gold_transferred_in: number
          gold_transferred_out: number
          id: string
          investment_cash_amount: number
          investment_cash_amount_usd: number
          investment_inflow_usd: number
          investment_outflow_usd: number
          investment_percentage: number
          investment_proceeds_amount: number
          investment_proceeds_amount_usd: number
          investment_purchase_amount: number
          investment_purchase_amount_usd: number
          investment_sale_amount: number
          investment_sale_amount_usd: number
          loan_disbursed_amount: number
          loan_disbursed_amount_usd: number
          loan_interest_accrued: number
          loan_interest_accrued_usd: number
          loan_interest_repaid: number
          loan_interest_repaid_usd: number
          loan_principal_repaid: number
          loan_principal_repaid_usd: number
          loan_repayment_amount: number
          loan_repayment_amount_usd: number
          opening_gold_quantity: number
          opening_investment_usd: number
          opening_loan_balance: number
          opening_loan_balance_usd: number
          opening_savings: number
          opening_savings_usd: number
          period: number
          repayment_cash_amount: number
          repayment_cash_amount_usd: number
          repayment_percentage: number
          saving_amount: number
          saving_amount_usd: number
          saving_percentage: number
          savings_inflow: number
          savings_inflow_usd: number
          savings_outflow: number
          savings_outflow_usd: number
          spending_amount: number
          spending_amount_usd: number
          spending_cash_amount: number
          spending_cash_amount_usd: number
          spending_percentage: number
          transfer_in_amount: number
          transfer_in_amount_usd: number
          updated_at: string
          user_id: string
          withdrawal_amount: number
          withdrawal_amount_usd: number
          withdrawal_cash_amount: number
          withdrawal_cash_amount_usd: number
          withdrawal_percentage: number
        }
        SetofOptions: {
          from: "*"
          to: "financial_pot"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      record_gold_buy_blockchain_transaction: {
        Args: {
          p_blockchain_code: string
          p_country_code: string
          p_explorer_url: string
          p_transaction: Json
          p_transaction_state_id: string
          p_tx_hash: string
          p_user_id: string
        }
        Returns: string
      }
      record_gold_sell_blockchain_transaction: {
        Args: {
          p_blockchain_code: string
          p_country_code: string
          p_explorer_url: string
          p_seller_id: string
          p_transaction: Json
          p_transaction_state_id: string
          p_tx_hash: string
        }
        Returns: string
      }
      record_gold_transfer_blockchain_transaction: {
        Args: {
          p_blockchain_code: string
          p_country_code: string
          p_explorer_url: string
          p_sender_id: string
          p_transaction: Json
          p_transaction_state_id: string
          p_tx_hash: string
        }
        Returns: string
      }
      record_liquidation_blockchain_submission: {
        Args: { p_queue_id: string; p_tx_hash: string }
        Returns: Json
      }
      record_my_token_adjustment_blockchain_transaction: {
        Args: {
          p_adjustment_request_id: string
          p_explorer_url?: string
          p_treasury_address: string
          p_tx_hash: string
        }
        Returns: Json
      }
      record_non_earning_transfer_activity: {
        Args: {
          p_amount: number
          p_amount_usd: number
          p_country_code: string
          p_currency_code: string
          p_idempotency_key: string
          p_metadata?: Json
          p_source_reference: string
          p_source_transaction_id: string
          p_user_id: string
        }
        Returns: Json
      }
      redeem_loyalty_points_for_transfer_fee: {
        Args: {
          p_country_code: string
          p_currency_code: string
          p_fee_amount: number
          p_fee_amount_usd: number
          p_points_per_usd: number
          p_points_to_redeem: number
          p_source_reference: string
          p_source_transaction_id: string
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
          p_user_id: string
        }
        Returns: Json
      }
      release_my_token_adjustment_execution: {
        Args: { p_adjustment_request_id: string }
        Returns: Json
      }
      render_notification_template: {
        Args: { p_payload: Json; p_template: string }
        Returns: string
      }
      requeue_reviewed_liquidation_blockchain_job: {
        Args: { p_queue_id: string; p_resolution_note: string }
        Returns: Json
      }
      resolve_component_amount: {
        Args: {
          p_component_type: Database["public"]["Enums"]["ComponentType"]
          p_pricing: Database["public"]["CompositeTypes"]["pricing_result"]
        }
        Returns: number
      }
      resolve_financial_behavior: {
        Args: {
          p_borrowing_usd: number
          p_investment_usd: number
          p_saving_usd: number
          p_spending_usd: number
        }
        Returns: {
          behavior: Database["public"]["Enums"]["financial_behavior_type"]
          borrower_score_percentage: number
          investor_score_percentage: number
          rule_id: string
          saver_score_percentage: number
          shopper_score_percentage: number
        }[]
      }
      resolve_principal_mode: {
        Args: {
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
        }
        Returns: Database["public"]["Enums"]["PrincipalMode"]
      }
      reverse_loyalty_points: {
        Args: {
          p_idempotency_key: string
          p_metadata?: Json
          p_original_event_id: string
          p_source_reference: string
        }
        Returns: Json
      }
      round_down: { Args: { p_value: number }; Returns: number }
      run_monthly_government_tax_batches: { Args: never; Returns: Json }
      run_weekly_agent_commission_batches: { Args: never; Returns: Json }
      save_gold_buy_execution_context: {
        Args: { p_context: Json; p_transaction_state_id: string }
        Returns: undefined
      }
      save_liquidation_blockchain_signed_payload: {
        Args: { p_queue_id: string; p_signed_payload: Json }
        Returns: Json
      }
      submit_my_verification_document: {
        Args: { p_document_type: string; p_file_name: string; p_url: string }
        Returns: Json
      }
      sync_my_credit_agent_currency_accounts: {
        Args: { p_country_code: string }
        Returns: Json
      }
      update_collateral_snapshot: {
        Args: {
          p_country_code: string
          p_credit: number
          p_debit: number
          p_fiscal_year: number
          p_period: number
          p_user_id: string
        }
        Returns: undefined
      }
      update_gl_balance_snapshot: {
        Args: {
          p_components: Database["public"]["CompositeTypes"]["posting_component"][]
          p_country_code: string
          p_currency_code: string
          p_fiscal_year: number
          p_mappings: Database["public"]["Tables"]["transaction_gl_mapping"]["Row"][]
          p_period: number
        }
        Returns: undefined
      }
      update_gold_rate_from_ounce_price: {
        Args: { p_price_per_ounce: number }
        Returns: number
      }
      update_loan_snapshot: {
        Args: {
          p_country_code: string
          p_credit_interest: number
          p_credit_principal: number
          p_debit_interest: number
          p_debit_principal: number
          p_fiscal_year: number
          p_loan_id: string
          p_period: number
          p_user_id: string
        }
        Returns: undefined
      }
      update_my_agent_commission_settlement_batch: {
        Args: { p_action: string; p_batch_id: string }
        Returns: Json
      }
      update_my_government_tax_settlement_batch: {
        Args: { p_action: string; p_batch_id: string }
        Returns: Json
      }
      update_my_transaction_state: {
        Args: {
          p_message?: string
          p_status: Database["public"]["Enums"]["TransactionStatus"]
          p_transaction_id: string
        }
        Returns: undefined
      }
      update_token_adjustment_request_status: {
        Args: {
          p_adjustment_request_id: string
          p_ip_address?: string
          p_status: string
        }
        Returns: Json
      }
      update_wallet_balance_snapshot: {
        Args: {
          p_blockchain_code?: string
          p_country_code: string
          p_currency_code: string
          p_fee_amount?: number
          p_fiscal_year: number
          p_period: number
          p_receiver_amount: number
          p_receiver_id: string
          p_receiver_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
          p_sender_amount: number
          p_sender_id: string
          p_sender_wallet_owner: Database["public"]["Enums"]["WalletOwnerType"]
          p_transaction_type: Database["public"]["Enums"]["TransactionType"]
          p_treasury_id: string
        }
        Returns: undefined
      }
      upsert_country_currency: {
        Args: {
          p_country_code: string
          p_currency_code: string
          p_is_active: boolean
        }
        Returns: {
          country_code: string
          created_at: string
          created_by: string
          currency_code: string
          id: string
          is_active: boolean
          is_reporting: boolean
          updated_at: string
          updated_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "country_currencies"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      upsert_fiat_currency_rate: {
        Args: { p_currency_code: string; p_rate_to_usd: number }
        Returns: Json
      }
      upsert_my_user_basic_profile: {
        Args: {
          p_dob?: string
          p_first_name?: string
          p_gender?: string
          p_middle_name?: string
          p_nationality?: string
          p_surname?: string
        }
        Returns: Json
      }
      upsert_my_user_contact_details: {
        Args: {
          p_city?: string
          p_country_code?: string
          p_email?: string
          p_phone?: string
          p_province_state?: string
          p_residential_address?: string
        }
        Returns: Json
      }
      upsert_my_user_kyc_details: {
        Args: {
          p_expiry_date?: string
          p_id_number?: string
          p_id_type?: string
          p_occupation?: string
          p_source_of_funds?: string
          p_tax_number?: string
        }
        Returns: Json
      }
      upsert_operational_country: {
        Args: {
          p_calling_code: string
          p_country_code: string
          p_is_active: boolean
          p_name: string
        }
        Returns: {
          calling_code: string | null
          country_code: string
          created_at: string
          created_by: string
          id: string
          is_active: boolean
          name: string
          time_zone: string | null
          updated_at: string
          updated_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "operational_country"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      upsert_supported_currency: {
        Args: {
          p_currency_code: string
          p_decimals: number
          p_is_active: boolean
          p_name: string
          p_rate_url: string
          p_symbol: string
        }
        Returns: {
          created_at: string
          created_by: string
          currency_category: Database["public"]["Enums"]["CurrencyCategory"]
          currency_code: string
          decimals: number
          id: string
          is_active: boolean
          name: string
          rate_api: string
          symbol: string
          updated_at: string
          updated_by: string | null
        }
        SetofOptions: {
          from: "*"
          to: "supported_currency"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      user_has_role:
        | {
            Args: {
              p_allowed_roles: Database["public"]["Enums"]["Role"][]
              p_user_id: string
            }
            Returns: boolean
          }
        | {
            Args: { p_allowed_roles: string[]; p_user_id: string }
            Returns: boolean
          }
      validate_components: {
        Args: {
          p_components: Database["public"]["CompositeTypes"]["posting_component"][]
        }
        Returns: Database["public"]["CompositeTypes"]["posting_component"][]
      }
      validate_gold_sell_available_balance: {
        Args: {
          p_blockchain_code: string
          p_country_code: string
          p_seller_id: string
          p_token_quantity: number
        }
        Returns: undefined
      }
      verify_registration_auth_creation: {
        Args: { p_attempt_id: string; p_user_id: string }
        Returns: boolean
      }
      verify_user_kyc: {
        Args: { p_comments?: string; p_decision: string; p_user_id: string }
        Returns: Json
      }
    }
    Enums: {
      AdjustmentStatus:
        | "pending"
        | "approved"
        | "rejected"
        | "minted"
        | "burned"
        | "cancelled"
      AssetAdjustmentType: "buy" | "sell"
      AssetType: "gold"
      AuditActionType:
        | "user_deactivated"
        | "user_deleted"
        | "user_activated"
        | "user_role_changed"
        | "agent_created"
        | "agent_deactivated"
        | "agent_activated"
        | "merchant_created"
        | "merchant_deactivated"
        | "merchant_activated"
        | "treasury_funded"
        | "agent_funded"
        | "treasury_fund_reversed"
        | "agent_fund_reversed"
        | "external_funding"
        | "external_funding_reversed"
        | "kyc_submitted"
        | "kyc_approved"
        | "kyc_rejected"
        | "cash_deposited"
        | "cash_transferred"
        | "cash_withdrawal"
        | "cash_deposit_reversed"
        | "cash_transfer_reversed"
        | "cash_withdrawal_reversed"
        | "loan_issued"
        | "loan_repaid"
        | "loan_liquidated"
        | "loan_reversed"
        | "minting_approved"
        | "minting_rejected"
        | "burning_approved"
        | "burning_rejected"
        | "token_minted"
        | "token_burned"
        | "token_minting_reversed"
        | "token_burning_reversed"
        | "gold_purchased"
        | "gold_sold"
        | "token_bought"
        | "token_sold"
        | "token_transferred"
        | "token_bought_reversed"
        | "token_sold_reversed"
        | "token_transfer_reversed"
        | "gl_mapping_updated"
        | "gl_created"
        | "gl_updated"
        | "language_added"
        | "language_deactivated"
        | "currency_added"
        | "currency_deactivated"
        | "agent_settlement_approved"
        | "agent_settlement_rejected"
        | "agent_settlement_drafted"
        | "agent_settlement_settled"
        | "agent_settlement_reversed"
        | "tax_settlement_approved"
        | "tax_settlement_rejected"
        | "tax_settlement_drafted"
        | "tax_settlement_settled"
        | "tax_settlement_reversed"
        | "merchant_settlement_approved"
        | "merchant_settlement_rejected"
        | "merchant_settlement_drafted"
        | "merchant_settlement_settled"
        | "merchant_settlement_reversed"
        | "referral_settlement_approved"
        | "referral_settlement_rejected"
        | "referral_settlement_drafted"
        | "referral_settlement_settled"
        | "referral_settlement_reversed"
        | "document_reversed"
        | "merchant_payment"
        | "merchant_payment_reversed"
        | "customer_direct_deposit"
        | "gold_purchase_reversed"
        | "credit_agent_funded"
        | "credit_agent_funding_reversed"
        | "credit_agent_cash_deposited"
        | "credit_agent_cash_withdrawn"
        | "credit_agent_cash_settled"
        | "agent_commission_settled"
      BlockchainLiquidationStatus:
        | "pending"
        | "sent"
        | "confirmed"
        | "failed"
        | "processing"
      BlockchainTxStatus: "pending" | "completed" | "failed"
      ComponentType:
        | "principal"
        | "transfer_fee"
        | "withdrawal_fee"
        | "transaction_fee"
        | "trading_spread"
        | "loan_fee"
        | "liquidation_fee"
        | "agent_commission"
        | "referral_commission"
        | "merchant_commission"
        | "loan_interest"
        | "government_tax"
        | "rounding_adjustment"
        | "payment_fee"
        | "deposit_fee"
        | "credit_agent_receivable"
      CurrencyCategory: "fiat" | "token"
      CustomerDepositType: "agent" | "bank" | "mobile" | "card" | "office"
      financial_activity_pot_type:
        | "deposit"
        | "withdrawal"
        | "spending"
        | "investment"
      financial_activity_type:
        | "deposit"
        | "withdrawal"
        | "spending"
        | "investment_buy"
        | "investment_sell"
        | "investment_transfer_in"
        | "investment_transfer_out"
        | "loan_disbursement"
        | "loan_repayment"
        | "loan_interest_accrual"
      financial_badge_metric:
        | "spending"
        | "saving"
        | "investment"
        | "borrowing"
        | "repayment"
      financial_behavior_scope: "period" | "fiscal_year"
      financial_behavior_type:
        | "shopper"
        | "saver"
        | "investor"
        | "borrower"
        | "balanced"
        | "neutral"
      financial_pot_type:
        | "deposit"
        | "withdrawal"
        | "spending"
        | "saving"
        | "investment"
      GamificationEventStatus:
        | "pending"
        | "processing"
        | "completed"
        | "ignored"
        | "failed"
        | "reversed"
      GamificationNotificationType:
        | "points_earned"
        | "level_up"
        | "level_down"
        | "badge_awarded"
        | "challenge_completed"
        | "reward_available"
      GenderType: "male" | "female" | "prefer_not_to_say"
      GlType: "asset" | "liability" | "revenue" | "expense" | "equity" | "token"
      GlUpdateStatus: "pending" | "approved" | "rejected"
      KycDocumentType: "national_id" | "passport" | "driver_license"
      KycStatus:
        | "pending"
        | "approved"
        | "rejected"
        | "under_review"
        | "verified"
        | "requires_update"
      LiquidationJobStatus:
        | "pending"
        | "processing"
        | "failed"
        | "completed"
        | "blockchain_processing"
        | "blockchain_confirmed"
        | "accounting_processing"
        | "accounting_failed"
      LoanEntryType:
        | "disbursement"
        | "disbursement_reversal"
        | "repayment"
        | "repayment_reversal"
        | "interest_accrual"
        | "liquidation"
      LoanStatus: "active" | "liquidated" | "reversed" | "closed"
      LoyaltyBadgeCategory:
        | "wallet"
        | "gold"
        | "lending"
        | "community"
        | "merchant"
        | "agent"
      LoyaltyBadgeCriteriaType:
        | "event_count"
        | "lifetime_points"
        | "tier_points"
        | "available_points"
      LoyaltyCapPeriodType: "daily" | "monthly"
      LoyaltyEventType:
        | "kyc_completed"
        | "user_deposit"
        | "user_transfer"
        | "merchant_payment"
        | "gold_token_buy"
        | "gold_token_sell"
        | "loan_repayment"
        | "loan_repayment_on_time_bonus"
        | "referral_completed"
        | "monthly_activity_bonus"
        | "challenge_completed"
        | "manual_adjustment"
        | "reversal"
        | "merchant_payment_fee_contribution"
      LoyaltyLedgerType: "earn" | "redeem" | "reverse" | "expire" | "adjustment"
      LoyaltyLevelChangeReason:
        | "account_created"
        | "points_earned"
        | "points_reversed"
        | "manual_adjustment"
      LoyaltyRuleCalculationType:
        | "fixed"
        | "amount_based"
        | "fixed_plus_amount"
        | "amount_band"
      MessageCategory: "info" | "success" | "warning" | "error"
      NotificationAudience:
        | "sender"
        | "receiver"
        | "initiator"
        | "beneficiary"
        | "agent"
        | "merchant"
        | "customer"
        | "system"
      NotificationType:
        | "deposit"
        | "withdrawal"
        | "transfer"
        | "buy"
        | "sell"
        | "disbursement"
        | "repayment"
        | "payment"
        | "liquidation"
        | "reversal"
        | "settlement"
      PrincipalMode: "gross" | "net" | "neutral" | "charges"
      ReconciliationAdjustmentStatus:
        | "pending"
        | "approved"
        | "rejected"
        | "executed"
        | "cancelled"
      ReconciliationAdjustmentType:
        | "gl_adjustment"
        | "wallet_adjustment"
        | "collateral_adjustment"
        | "asset_adjustment"
        | "sva_adjustment"
        | "tax_adjustment"
        | "commission_adjustment"
        | "token_supply_adjustment"
        | "reserve_adjustment"
      ReconciliationCheckType:
        | "gl_vs_wallet"
        | "gl_vs_gold_liability"
        | "gl_vs_collateral"
        | "gl_vs_sva"
        | "gl_vs_asset_reserve"
        | "reserve_coverage"
        | "tax_payable"
        | "agent_commission"
        | "merchant_commission"
        | "referral_earnings"
      ReconciliationStatus:
        | "pending"
        | "processing"
        | "passed"
        | "failed"
        | "completed"
        | "cancelled"
      Role:
        | "accounts"
        | "admin"
        | "compliance"
        | "agent"
        | "treasury"
        | "finance"
        | "customer"
        | "employee"
        | "audit"
        | "reserve_bank"
        | "merchant"
        | "operations"
        | "vendor"
      SettlementStatus:
        | "draft"
        | "pending"
        | "approved"
        | "settled"
        | "cancelled"
        | "partial"
        | "failed"
        | "processing"
      SpreadDirection: "buy" | "sell"
      TokenAdjustmentType: "minting" | "burning"
      TransactionStatus:
        | "waiting"
        | "detected"
        | "processing"
        | "success"
        | "failed"
      TransactionType:
        | "external_funding"
        | "treasury_funding"
        | "agent_deposit"
        | "agent_funding"
        | "agent_settlement"
        | "agent_settlement_sub_tx"
        | "agent_commission_settlement"
        | "customer_direct_deposit"
        | "credit_agent_funding"
        | "credit_agent_cash_deposit"
        | "credit_agent_cash_withdrawal"
        | "credit_agent_cash_settlement"
        | "credit_agent_settlement"
        | "cash_deposit"
        | "cash_transfer"
        | "cash_withdrawal"
        | "merchant_payment"
        | "merchant_withdrawal"
        | "merchant_commission_settlement"
        | "gold_token_buy"
        | "gold_token_sell"
        | "gold_token_transfer"
        | "gold_token_buy_sub_tx"
        | "gold_token_sell_sub_tx"
        | "gold_inventory_purchase"
        | "gold_inventory_sell"
        | "loan_disbursement"
        | "loan_repayment"
        | "loan_interest_accrual"
        | "loan_liquidation"
        | "loan_liquidation_sub_tx"
        | "gold_token_mint"
        | "gold_token_burn"
        | "referral_commission_settlement"
        | "gl_adjustment"
        | "government_tax_clearing"
        | "external_funding_reversal"
        | "treasury_funding_reversal"
        | "agent_deposit_reversal"
        | "agent_funding_reversal"
        | "agent_settlement_reversal"
        | "agent_settlement_sub_tx_reversal"
        | "agent_commission_settlement_reversal"
        | "customer_direct_deposit_reversal"
        | "credit_agent_funding_reversal"
        | "credit_agent_cash_deposit_reversal"
        | "credit_agent_cash_withdrawal_reversal"
        | "credit_agent_cash_settlement_reversal"
        | "credit_agent_settlement_reversal"
        | "cash_deposit_reversal"
        | "cash_transfer_reversal"
        | "cash_withdrawal_reversal"
        | "merchant_payment_reversal"
        | "merchant_withdrawal_reversal"
        | "merchant_commission_settlement_reversal"
        | "gold_token_buy_reversal"
        | "gold_token_sell_reversal"
        | "gold_token_transfer_reversal"
        | "gold_token_buy_sub_tx_reversal"
        | "gold_token_sell_sub_tx_reversal"
        | "gold_inventory_purchase_reversal"
        | "gold_inventory_sell_reversal"
        | "loan_disbursement_reversal"
        | "loan_repayment_reversal"
        | "loan_interest_accrual_reversal"
        | "loan_liquidation_reversal"
        | "loan_liquidation_sub_tx_reversal"
        | "gold_token_mint_reversal"
        | "gold_token_burn_reversal"
        | "referral_commission_settlement_reversal"
        | "gl_adjustment_reversal"
        | "government_tax_clearing_reversal"
      Uom: "gram"
      UserStatus: "active" | "blocked" | "suspended" | "deleted"
      VerificationDocumentType:
        | "id_front"
        | "id_back"
        | "proof_of_address"
        | "selfie"
      WalletOwnerType:
        | "customer"
        | "agent"
        | "treasury"
        | "employee"
        | "merchant"
    }
    CompositeTypes: {
      amount_config: {
        percentage: number | null
        fixed_amount: number | null
        min_amount: number | null
        max_amount: number | null
      }
      component_totals: {
        principal_amount: number | null
        others_amount: number | null
      }
      notification_message: {
        notification_type:
          | Database["public"]["Enums"]["NotificationType"]
          | null
        title: string | null
        body: string | null
        payload: Json | null
      }
      posting_component: {
        component_type: Database["public"]["Enums"]["ComponentType"] | null
        debit_amount: number | null
        credit_amount: number | null
      }
      pricing_result: {
        fee: number | null
        tax: number | null
        spread: number | null
        commission: number | null
        quantity: number | null
        fiat_received: number | null
        gold_price: number | null
      }
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      AdjustmentStatus: [
        "pending",
        "approved",
        "rejected",
        "minted",
        "burned",
        "cancelled",
      ],
      AssetAdjustmentType: ["buy", "sell"],
      AssetType: ["gold"],
      AuditActionType: [
        "user_deactivated",
        "user_deleted",
        "user_activated",
        "user_role_changed",
        "agent_created",
        "agent_deactivated",
        "agent_activated",
        "merchant_created",
        "merchant_deactivated",
        "merchant_activated",
        "treasury_funded",
        "agent_funded",
        "treasury_fund_reversed",
        "agent_fund_reversed",
        "external_funding",
        "external_funding_reversed",
        "kyc_submitted",
        "kyc_approved",
        "kyc_rejected",
        "cash_deposited",
        "cash_transferred",
        "cash_withdrawal",
        "cash_deposit_reversed",
        "cash_transfer_reversed",
        "cash_withdrawal_reversed",
        "loan_issued",
        "loan_repaid",
        "loan_liquidated",
        "loan_reversed",
        "minting_approved",
        "minting_rejected",
        "burning_approved",
        "burning_rejected",
        "token_minted",
        "token_burned",
        "token_minting_reversed",
        "token_burning_reversed",
        "gold_purchased",
        "gold_sold",
        "token_bought",
        "token_sold",
        "token_transferred",
        "token_bought_reversed",
        "token_sold_reversed",
        "token_transfer_reversed",
        "gl_mapping_updated",
        "gl_created",
        "gl_updated",
        "language_added",
        "language_deactivated",
        "currency_added",
        "currency_deactivated",
        "agent_settlement_approved",
        "agent_settlement_rejected",
        "agent_settlement_drafted",
        "agent_settlement_settled",
        "agent_settlement_reversed",
        "tax_settlement_approved",
        "tax_settlement_rejected",
        "tax_settlement_drafted",
        "tax_settlement_settled",
        "tax_settlement_reversed",
        "merchant_settlement_approved",
        "merchant_settlement_rejected",
        "merchant_settlement_drafted",
        "merchant_settlement_settled",
        "merchant_settlement_reversed",
        "referral_settlement_approved",
        "referral_settlement_rejected",
        "referral_settlement_drafted",
        "referral_settlement_settled",
        "referral_settlement_reversed",
        "document_reversed",
        "merchant_payment",
        "merchant_payment_reversed",
        "customer_direct_deposit",
        "gold_purchase_reversed",
        "credit_agent_funded",
        "credit_agent_funding_reversed",
        "credit_agent_cash_deposited",
        "credit_agent_cash_withdrawn",
        "credit_agent_cash_settled",
        "agent_commission_settled",
      ],
      BlockchainLiquidationStatus: [
        "pending",
        "sent",
        "confirmed",
        "failed",
        "processing",
      ],
      BlockchainTxStatus: ["pending", "completed", "failed"],
      ComponentType: [
        "principal",
        "transfer_fee",
        "withdrawal_fee",
        "transaction_fee",
        "trading_spread",
        "loan_fee",
        "liquidation_fee",
        "agent_commission",
        "referral_commission",
        "merchant_commission",
        "loan_interest",
        "government_tax",
        "rounding_adjustment",
        "payment_fee",
        "deposit_fee",
        "credit_agent_receivable",
      ],
      CurrencyCategory: ["fiat", "token"],
      CustomerDepositType: ["agent", "bank", "mobile", "card", "office"],
      financial_activity_pot_type: [
        "deposit",
        "withdrawal",
        "spending",
        "investment",
      ],
      financial_activity_type: [
        "deposit",
        "withdrawal",
        "spending",
        "investment_buy",
        "investment_sell",
        "investment_transfer_in",
        "investment_transfer_out",
        "loan_disbursement",
        "loan_repayment",
        "loan_interest_accrual",
      ],
      financial_badge_metric: [
        "spending",
        "saving",
        "investment",
        "borrowing",
        "repayment",
      ],
      financial_behavior_scope: ["period", "fiscal_year"],
      financial_behavior_type: [
        "shopper",
        "saver",
        "investor",
        "borrower",
        "balanced",
        "neutral",
      ],
      financial_pot_type: [
        "deposit",
        "withdrawal",
        "spending",
        "saving",
        "investment",
      ],
      GamificationEventStatus: [
        "pending",
        "processing",
        "completed",
        "ignored",
        "failed",
        "reversed",
      ],
      GamificationNotificationType: [
        "points_earned",
        "level_up",
        "level_down",
        "badge_awarded",
        "challenge_completed",
        "reward_available",
      ],
      GenderType: ["male", "female", "prefer_not_to_say"],
      GlType: ["asset", "liability", "revenue", "expense", "equity", "token"],
      GlUpdateStatus: ["pending", "approved", "rejected"],
      KycDocumentType: ["national_id", "passport", "driver_license"],
      KycStatus: [
        "pending",
        "approved",
        "rejected",
        "under_review",
        "verified",
        "requires_update",
      ],
      LiquidationJobStatus: [
        "pending",
        "processing",
        "failed",
        "completed",
        "blockchain_processing",
        "blockchain_confirmed",
        "accounting_processing",
        "accounting_failed",
      ],
      LoanEntryType: [
        "disbursement",
        "disbursement_reversal",
        "repayment",
        "repayment_reversal",
        "interest_accrual",
        "liquidation",
      ],
      LoanStatus: ["active", "liquidated", "reversed", "closed"],
      LoyaltyBadgeCategory: [
        "wallet",
        "gold",
        "lending",
        "community",
        "merchant",
        "agent",
      ],
      LoyaltyBadgeCriteriaType: [
        "event_count",
        "lifetime_points",
        "tier_points",
        "available_points",
      ],
      LoyaltyCapPeriodType: ["daily", "monthly"],
      LoyaltyEventType: [
        "kyc_completed",
        "user_deposit",
        "user_transfer",
        "merchant_payment",
        "gold_token_buy",
        "gold_token_sell",
        "loan_repayment",
        "loan_repayment_on_time_bonus",
        "referral_completed",
        "monthly_activity_bonus",
        "challenge_completed",
        "manual_adjustment",
        "reversal",
        "merchant_payment_fee_contribution",
      ],
      LoyaltyLedgerType: ["earn", "redeem", "reverse", "expire", "adjustment"],
      LoyaltyLevelChangeReason: [
        "account_created",
        "points_earned",
        "points_reversed",
        "manual_adjustment",
      ],
      LoyaltyRuleCalculationType: [
        "fixed",
        "amount_based",
        "fixed_plus_amount",
        "amount_band",
      ],
      MessageCategory: ["info", "success", "warning", "error"],
      NotificationAudience: [
        "sender",
        "receiver",
        "initiator",
        "beneficiary",
        "agent",
        "merchant",
        "customer",
        "system",
      ],
      NotificationType: [
        "deposit",
        "withdrawal",
        "transfer",
        "buy",
        "sell",
        "disbursement",
        "repayment",
        "payment",
        "liquidation",
        "reversal",
        "settlement",
      ],
      PrincipalMode: ["gross", "net", "neutral", "charges"],
      ReconciliationAdjustmentStatus: [
        "pending",
        "approved",
        "rejected",
        "executed",
        "cancelled",
      ],
      ReconciliationAdjustmentType: [
        "gl_adjustment",
        "wallet_adjustment",
        "collateral_adjustment",
        "asset_adjustment",
        "sva_adjustment",
        "tax_adjustment",
        "commission_adjustment",
        "token_supply_adjustment",
        "reserve_adjustment",
      ],
      ReconciliationCheckType: [
        "gl_vs_wallet",
        "gl_vs_gold_liability",
        "gl_vs_collateral",
        "gl_vs_sva",
        "gl_vs_asset_reserve",
        "reserve_coverage",
        "tax_payable",
        "agent_commission",
        "merchant_commission",
        "referral_earnings",
      ],
      ReconciliationStatus: [
        "pending",
        "processing",
        "passed",
        "failed",
        "completed",
        "cancelled",
      ],
      Role: [
        "accounts",
        "admin",
        "compliance",
        "agent",
        "treasury",
        "finance",
        "customer",
        "employee",
        "audit",
        "reserve_bank",
        "merchant",
        "operations",
        "vendor",
      ],
      SettlementStatus: [
        "draft",
        "pending",
        "approved",
        "settled",
        "cancelled",
        "partial",
        "failed",
        "processing",
      ],
      SpreadDirection: ["buy", "sell"],
      TokenAdjustmentType: ["minting", "burning"],
      TransactionStatus: [
        "waiting",
        "detected",
        "processing",
        "success",
        "failed",
      ],
      TransactionType: [
        "external_funding",
        "treasury_funding",
        "agent_deposit",
        "agent_funding",
        "agent_settlement",
        "agent_settlement_sub_tx",
        "agent_commission_settlement",
        "customer_direct_deposit",
        "credit_agent_funding",
        "credit_agent_cash_deposit",
        "credit_agent_cash_withdrawal",
        "credit_agent_cash_settlement",
        "credit_agent_settlement",
        "cash_deposit",
        "cash_transfer",
        "cash_withdrawal",
        "merchant_payment",
        "merchant_withdrawal",
        "merchant_commission_settlement",
        "gold_token_buy",
        "gold_token_sell",
        "gold_token_transfer",
        "gold_token_buy_sub_tx",
        "gold_token_sell_sub_tx",
        "gold_inventory_purchase",
        "gold_inventory_sell",
        "loan_disbursement",
        "loan_repayment",
        "loan_interest_accrual",
        "loan_liquidation",
        "loan_liquidation_sub_tx",
        "gold_token_mint",
        "gold_token_burn",
        "referral_commission_settlement",
        "gl_adjustment",
        "government_tax_clearing",
        "external_funding_reversal",
        "treasury_funding_reversal",
        "agent_deposit_reversal",
        "agent_funding_reversal",
        "agent_settlement_reversal",
        "agent_settlement_sub_tx_reversal",
        "agent_commission_settlement_reversal",
        "customer_direct_deposit_reversal",
        "credit_agent_funding_reversal",
        "credit_agent_cash_deposit_reversal",
        "credit_agent_cash_withdrawal_reversal",
        "credit_agent_cash_settlement_reversal",
        "credit_agent_settlement_reversal",
        "cash_deposit_reversal",
        "cash_transfer_reversal",
        "cash_withdrawal_reversal",
        "merchant_payment_reversal",
        "merchant_withdrawal_reversal",
        "merchant_commission_settlement_reversal",
        "gold_token_buy_reversal",
        "gold_token_sell_reversal",
        "gold_token_transfer_reversal",
        "gold_token_buy_sub_tx_reversal",
        "gold_token_sell_sub_tx_reversal",
        "gold_inventory_purchase_reversal",
        "gold_inventory_sell_reversal",
        "loan_disbursement_reversal",
        "loan_repayment_reversal",
        "loan_interest_accrual_reversal",
        "loan_liquidation_reversal",
        "loan_liquidation_sub_tx_reversal",
        "gold_token_mint_reversal",
        "gold_token_burn_reversal",
        "referral_commission_settlement_reversal",
        "gl_adjustment_reversal",
        "government_tax_clearing_reversal",
      ],
      Uom: ["gram"],
      UserStatus: ["active", "blocked", "suspended", "deleted"],
      VerificationDocumentType: [
        "id_front",
        "id_back",
        "proof_of_address",
        "selfie",
      ],
      WalletOwnerType: [
        "customer",
        "agent",
        "treasury",
        "employee",
        "merchant",
      ],
    },
  },
} as const
