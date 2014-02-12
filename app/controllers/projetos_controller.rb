class ProjetosController < ApplicationController
  before_action :authenticate_usuario!
  before_filter :checa_autorizacao, :only => [:edit, :destroy]

  # fix temporário devido a problemas de compatibilidade com o cancan
  def checa_autorizacao
    @projeto = Projeto.find params[:id]
    if !@projeto.autorizacao(current_user, params[:action])
      redirect_to projetos_path, notice: "Você não está autorizado a executar essa operação"
      false
    end
    true
  end


  # GET /projetos
  # GET /projetos.json
  def index
    if params["tipo"] == "TODOS" || params["tipo"].nil?
      @tipo = "TODOS"
      if current_usuario.role == "admin"
        @projetos = Projeto.where(:super_projeto_id => nil).order(:nome).
          map{|superP| [superP, superP.sub_projetos.sort{|a,b| a.nome <=> b.nome}]}
      elsif current_usuario.role == "diretor"
        @projetos = current_usuario.projetos_coordenados.map{|proj| proj.super_projeto.nil? ? proj : proj.super_projeto}.uniq.
          map{|superP| [superP, superP.sub_projetos.where(:id => current_usuario.projetos_coordenados.
                map{|z| z.id})]}
      else
        @projetos = current_usuario.projetos.map{|proj| proj.super_projeto.nil? ? proj : proj.super_projeto}.uniq.
          map{|superP| [superP, superP.sub_projetos.where(:id => current_usuario.projetos.
                map{|z| z.id})]}
      end
    elsif params["tipo"] == "sub_projetos"
      @tipo = "sub_projetos"
      if current_usuario.role == "admin"
        @projetos = Projeto.all.select{|proj| !proj.super_projeto.nil?}.map{|sub| [sub,[]]}
      else
        @projetos = current_usuario.projetos_coordenados.
          select{|proj| !proj.super_projeto.nil?}.map{|sub| [sub,[]]}
      end
    elsif params["tipo"] == "super_projetos"
      @tipo = "super_projetos"
      if current_usuario.role == "admin"
        @projetos = Projeto.all.select{|proj| proj.super_projeto.nil?}.map{|sub| [sub,[]]}
      else
        @projetos = current_usuario.projetos_coordenados.
          select{|proj| proj.super_projeto.nil?}.map{|sup| [sup,[]]}
      end
    end
    @projeto = Projeto.new

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @projetos }
    end
  end

  # GET /projetos/1/edit
  def edit
    authorize! :read, Projeto
    @projeto = Projeto.find(params[:id])
    @autorizado = (@projeto.autorizacao(current_usuario, "update") ||
      !((@projeto.workons.select{|z| z.coordenadores_ids.include? current_usuario.id}).blank?))
    edit_attr
  end

  # POST /projetos
  # POST /projetos.json
  def create
    authorize! :create, Projeto
    @projeto = Projeto.new(projetos_params)
    if @projeto.save
      Workon.new(usuario: current_user, projeto: @projeto, permissao: Permissao.find_by(nome: "admin")).save
      redirect_to projetos_path, notice: I18n.t("projetos.create.success")
    else
      puts @projeto.errors
      flash[:errors] = I18n.t("projetos.create.failure")
      redirect_to projetos_path
    end
  end

  # PATCH /projetos/1
  # PATCH /projetos/1.json
  def update
    @projeto = Projeto.find(params[:id])
    if params[:commit] == "Filtra"
      @autorizado = (@projeto.autorizacao(current_usuario, "update") ||
        !((@projeto.workons.select{|z| z.coordenadores_ids.include? current_usuario.id}).blank?))
      edit_attr
      inicio = (/^\d\d?\/\d\d?\/\d{2}\d{2}?$/ =~ params[:inicio]).nil? ? nil : params[:inicio].split("/").reverse.join("-").to_date
      fim = (/^\d\d?\/\d\d?\/\d{2}\d{2}?$/ =~ params[:fim]).nil? ? nil : params[:fim].split("/").reverse.join("-").to_date
      @lista_atividades = @projeto.atividades.periodo(inicio .. fim ).usuario(params[:usuario_id].to_i).
        aprovacao(params[:aprovacao].to_i).limit(100).group_by{|atividade| atividade.dia}
      render :edit
    else
      authorize! :update, Projeto
      return unless checa_autorizacao
      boards = @projeto.boards.to_a
      #lidar com boards
      unless params[:trello].blank?
        params[:trello].each do |id|
          repetido = false
          boards.each_with_index do |c, i|
            if id == c.board_id
              repetido = true
              boards.delete_at i
            end
          end
          unless repetido
            board = Board.new
            board.projeto = @projeto
            board.board_id = id
            board.save
          end
        end
      end
      unless params[:dados].blank?
        params[:dados].each do |campo_id, valor|
          dado = Dado.find_or_create_by(campo_id: campo_id, usuario_id: current_user.id)
          dado.valor = valor
          dado.save
        end
      end
      boards.each do |b|
        b.destroy
      end
      #lidar com subprojetos
      failure = false
      if params[:super_projeto] == "true"
        params[:sub_projetos].each do |index, sub|
          subprojeto = Projeto.find(sub["id"].to_i)
          if sub["filho"].nil? && subprojeto.super_projeto_id == @projeto.id
            failure ||= !(subprojeto.update super_projeto_id: nil)
          elsif !(sub["filho"].nil?)
            if !subprojeto.sub_projetos.blank?
              return (redirect_to :back, :alert => I18n.t("projetos.update.cant_be_sub", projeto_nome: subprojeto.nome ))
            else
              failure ||= !(subprojeto.update super_projeto_id: @projeto.id)
            end
          end
        end
        @projeto.update super_projeto_id: nil
      else
        @projeto.sub_projetos.each{|sub| sub.update super_projeto_id: nil}
      end
      failure ||= !(@projeto.update (projetos_params))
      @projeto.update super_projeto_id: nil if params[:super_projeto] == "true"
      respond_to do |format|
        if !failure
          format.html { redirect_to edit_projeto_path(@projeto), notice: I18n.t("projetos.update.success") }
          format.json { head :no_content }
        else
          format.html { redirect_to edit_projeto_path(@projeto), notice: I18n.t("projetos.update.failure") }
          format.json { render json: @projeto.errors, status: :unprocessable_entity }
        end
      end
    end
  end

  # DELETE /projetos/1
  # DELETE /projetos/1.json
  def destroy
    authorize! :destroy, Projeto
    @projeto = Projeto.find(params[:id])
    @projeto.destroy
    respond_to do |format|
      format.html { redirect_to projetos_url }
      format.json { head :no_content }
    end
  end

  def campos_cadastro
    authorize! :criar_campos, Usuario
    @projeto = Projeto.find params[:id]
    @projeto.campos.build if @projeto.campos.blank?
  end

  private
    def projetos_params
      params.require(:projeto).permit(:data_de_inicio, :descricao, :nome, :super_projeto_id,
        workons_attributes: [:id, :usuario_id,:permissao_id, :_destroy, {:coordenacoes => []}],
        sub_projetos: [:id, :filho],
        campos_attributes: [:id, :categoria, :nome, :tipo, :formato, :_destroy]
      )
    end

    def edit_attr
      @usuarios_select = @projeto.usuarios.map{|user| [user.nome, user.id] }.unshift(["Usuário - Todos", -1])
      @aprovacoes = [["Aprovacao - Todas", 2], ["Aprovada", 1], ["Reprovada", 0], ["Não Vista", nil]]
      @lista_atividades = @projeto.atividades.limit(100).group_by{|atividade| atividade.dia} if @autorizado
      @filhos_for_select  = Projeto.all.sort{ |projeto|
        @projeto.sub_projetos.include?(projeto) ? -1 : 1}.
          reject{|projeto| projeto == @projeto}.
            map{|filho| [filho.nome, filho.id]}
      @pais_for_select = Projeto.find_all_by_super_projeto_id(nil).
        sort{|a, b| a.nome <=> b.nome}.
          reject{|projeto| projeto == @projeto}.
            map{|proj| [proj.nome, proj.id]}
      @eh_super_projeto = @projeto.super_projeto.blank?
      @usuarios = Usuario.all.order(nome: :asc).collect {|u| [u.nome, u.id]}
      @hoje = Date.today
      @equipe = @projeto.usuarios.pluck(:nome).sort
      @inicio = params[:inicio].try(:to_date) || @hoje.beginning_of_month
      @fim = params[:fim].try(:to_date) || @hoje.end_of_month
      @ausencias = Ausencia.joins(:dia).where(dia: {data: @inicio..@fim}, projeto_id: @projeto.id).group_by{|x| x.dia.data}
      @atividades = Atividade.joins(:dia).where(dia: {data: @inicio..@fim}, projeto_id: @projeto.id).group_by{|x| x.dia.data}
      @permissoes = Permissao.order(nome: :desc).collect{|p| [p.nome, p.id]}
    end

end
