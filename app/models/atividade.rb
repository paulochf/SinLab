class Atividade < ActiveRecord::Base
  attr_accessible :dia_id, :horas, :observacao, :mes_id, :projeto_id, :user_id, :aprovacao
  attr_accessible :aprovado, :reprovado
  attr_accessible :valor_da_bolsa_fau, :horas_da_bolsa_fau, :funcao, :data_admissao_fau, :data_demissao_fau

	belongs_to :mes
	belongs_to :dia
	belongs_to :projeto

  def data
    mes = Mes.find mes_id
    Date.new(mes.ano, mes.numero, Dia.find(dia_id).numero)
  end

  def bar_width
		width = horas.nil? ? "0" : (horas / 360).to_s
		width + "%"
	end

end