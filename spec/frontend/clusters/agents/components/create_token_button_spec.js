import { GlButton, GlTooltip, GlModal, GlFormInput, GlFormTextarea, GlAlert } from '@gitlab/ui';
import Vue from 'vue';
import VueApollo from 'vue-apollo';
import createMockApollo from 'helpers/mock_apollo_helper';
import waitForPromises from 'helpers/wait_for_promises';
import { shallowMountExtended } from 'helpers/vue_test_utils_helper';
import { mockTracking } from 'helpers/tracking_helper';
import {
  EVENT_LABEL_MODAL,
  EVENT_ACTIONS_OPEN,
  TOKEN_NAME_LIMIT,
  TOKEN_STATUS_ACTIVE,
  MAX_LIST_COUNT,
} from '~/clusters/agents/constants';
import createNewAgentToken from '~/clusters/agents/graphql/mutations/create_new_agent_token.mutation.graphql';
import getClusterAgentQuery from '~/clusters/agents/graphql/queries/get_cluster_agent.query.graphql';
import AgentToken from '~/clusters_list/components/agent_token.vue';
import CreateTokenButton from '~/clusters/agents/components/create_token_button.vue';
import {
  clusterAgentToken,
  getTokenResponse,
  createAgentTokenErrorResponse,
} from '../../mock_data';

Vue.use(VueApollo);

describe('CreateTokenButton', () => {
  let wrapper;
  let apolloProvider;
  let trackingSpy;
  let createResponse;

  const clusterAgentId = 'cluster-agent-id';
  const cursor = {
    first: MAX_LIST_COUNT,
    last: null,
  };
  const agentName = 'cluster-agent';
  const projectPath = 'path/to/project';

  const defaultProvide = {
    agentName,
    projectPath,
    canAdminCluster: true,
  };
  const propsData = {
    clusterAgentId,
    cursor,
  };

  const findModal = () => wrapper.findComponent(GlModal);
  const findBtn = () => wrapper.findComponent(GlButton);
  const findInput = () => wrapper.findComponent(GlFormInput);
  const findTextarea = () => wrapper.findComponent(GlFormTextarea);
  const findAlert = () => wrapper.findComponent(GlAlert);
  const findTooltip = () => wrapper.findComponent(GlTooltip);
  const findAgentInstructions = () => findModal().findComponent(AgentToken);
  const findButtonByVariant = (variant) =>
    findModal()
      .findAll(GlButton)
      .wrappers.find((button) => button.props('variant') === variant);
  const findActionButton = () => findButtonByVariant('confirm');
  const findCancelButton = () => wrapper.findByTestId('agent-token-close-button');

  const expectDisabledAttribute = (element, disabled) => {
    if (disabled) {
      expect(element.attributes('disabled')).toBe('true');
    } else {
      expect(element.attributes('disabled')).toBeUndefined();
    }
  };

  const createMockApolloProvider = ({ mutationResponse }) => {
    createResponse = jest.fn().mockResolvedValue(mutationResponse);

    return createMockApollo([[createNewAgentToken, createResponse]]);
  };

  const writeQuery = () => {
    apolloProvider.clients.defaultClient.cache.writeQuery({
      query: getClusterAgentQuery,
      data: getTokenResponse.data,
      variables: {
        agentName,
        projectPath,
        tokenStatus: TOKEN_STATUS_ACTIVE,
        ...cursor,
      },
    });
  };

  const createWrapper = async ({ provideData = {} } = {}) => {
    wrapper = shallowMountExtended(CreateTokenButton, {
      apolloProvider,
      provide: {
        ...defaultProvide,
        ...provideData,
      },
      propsData,
      stubs: {
        GlModal,
        GlTooltip,
      },
    });
    wrapper.vm.$refs.modal.hide = jest.fn();

    trackingSpy = mockTracking(undefined, wrapper.element, jest.spyOn);
  };

  const mockCreatedResponse = (mutationResponse) => {
    apolloProvider = createMockApolloProvider({ mutationResponse });
    writeQuery();

    createWrapper();

    findInput().vm.$emit('input', 'new-token');
    findTextarea().vm.$emit('input', 'new-token-description');
    findActionButton().vm.$emit('click');

    return waitForPromises();
  };

  beforeEach(() => {
    createWrapper();
  });

  afterEach(() => {
    wrapper.destroy();
    apolloProvider = null;
    createResponse = null;
  });

  describe('create agent token action', () => {
    it('displays create agent token button', () => {
      expect(findBtn().text()).toBe('Create token');
    });

    describe('when user cannot create token', () => {
      beforeEach(() => {
        createWrapper({ provideData: { canAdminCluster: false } });
      });

      it('disabled the button', () => {
        expect(findBtn().attributes('disabled')).toBe('true');
      });

      it('shows a disabled tooltip', () => {
        expect(findTooltip().attributes('title')).toBe(
          'Requires a Maintainer or greater role to perform these actions',
        );
      });
    });

    describe('when user can create a token and clicks the button', () => {
      beforeEach(() => {
        findBtn().vm.$emit('click');
      });

      it('displays a token creation modal', () => {
        expect(findModal().isVisible()).toBe(true);
      });

      describe('initial state', () => {
        it('renders an input for the token name', () => {
          expect(findInput().exists()).toBe(true);
          expectDisabledAttribute(findInput(), false);
          expect(findInput().attributes('max-length')).toBe(TOKEN_NAME_LIMIT.toString());
        });

        it('renders a textarea for the token description', () => {
          expect(findTextarea().exists()).toBe(true);
          expectDisabledAttribute(findTextarea(), false);
        });

        it('renders a cancel button', () => {
          expect(findCancelButton().isVisible()).toBe(true);
          expectDisabledAttribute(findCancelButton(), false);
        });

        it('renders a disabled next button', () => {
          expect(findActionButton().text()).toBe('Create token');
          expectDisabledAttribute(findActionButton(), true);
        });

        it('sends tracking event for modal shown', () => {
          findModal().vm.$emit('show');
          expect(trackingSpy).toHaveBeenCalledWith(undefined, EVENT_ACTIONS_OPEN, {
            label: EVENT_LABEL_MODAL,
          });
        });
      });

      describe('when user inputs the token name', () => {
        beforeEach(() => {
          expectDisabledAttribute(findActionButton(), true);
          findInput().vm.$emit('input', 'new-token');
        });

        it('enables the next button', () => {
          expectDisabledAttribute(findActionButton(), false);
        });
      });

      describe('when user clicks the create-token button', () => {
        beforeEach(async () => {
          const loadingResponse = new Promise(() => {});
          await mockCreatedResponse(loadingResponse);

          findInput().vm.$emit('input', 'new-token');
          findActionButton().vm.$emit('click');
        });

        it('disables the create-token button', () => {
          expectDisabledAttribute(findActionButton(), true);
        });

        it('hides the cancel button', () => {
          expect(findCancelButton().exists()).toBe(false);
        });
      });

      describe('creating a new token', () => {
        beforeEach(async () => {
          await mockCreatedResponse(clusterAgentToken);
        });

        it('creates a token', () => {
          expect(createResponse).toHaveBeenCalledWith({
            input: { clusterAgentId, name: 'new-token', description: 'new-token-description' },
          });
        });

        it('shows agent instructions', () => {
          expect(findAgentInstructions().exists()).toBe(true);
        });

        it('renders a close button', () => {
          expect(findActionButton().isVisible()).toBe(true);
          expect(findActionButton().text()).toBe('Close');
          expectDisabledAttribute(findActionButton(), false);
        });
      });

      describe('error creating a new token', () => {
        beforeEach(async () => {
          await mockCreatedResponse(createAgentTokenErrorResponse);
        });

        it('displays the error message', async () => {
          expect(findAlert().text()).toBe(
            createAgentTokenErrorResponse.data.clusterAgentTokenCreate.errors[0],
          );
        });
      });
    });
  });
});
